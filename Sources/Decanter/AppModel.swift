import AppKit
import DecanterKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var bottles: [Bottle] = []
    @Published var selection: URL?
    @Published var installed: Set<String> = []
    /// Download progress keyed by component id or store name.
    @Published var progress: [String: Double] = [:]
    /// Label of the long task in flight; nil when idle.
    @Published var busy: String?
    @Published var error: String?
    @Published var notice: String?
    @Published var openRequest: URL?
    @Published var showNewBottle = false
    @AppStorage("setupDone") var setupDone = false

    init() { refresh() }

    var rosetta: Bool { Rosetta.isInstalled }
    var hasEngine: Bool { installed.contains("gptk") || installed.contains("wine") }
    var selected: Bottle? { bottles.first { $0.id == selection } }

    func refresh() {
        bottles = Bottle.all()
        installed = Set(Catalog.all.filter(Installer.isInstalled).map(\.id))
        if selected == nil { selection = bottles.first?.id }
    }

    /// Runs a long task with a status label; errors surface as an alert.
    func perform(_ label: String, _ work: @escaping @MainActor () async throws -> Void) {
        Task {
            busy = label
            defer { busy = nil; refresh() }
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }

    // MARK: Components

    func install(_ components: [Component]) {
        perform("Downloading components…") {
            for c in components {
                self.busy = "Installing \(c.name)…"
                self.progress[c.id] = 0
                defer { self.progress[c.id] = nil }
                try await Installer.install(c) { p in Task { @MainActor in self.progress[c.id] = p } }
                self.installed.insert(c.id)
            }
        }
    }

    func installRosetta() {
        perform("Installing Rosetta…") { try Rosetta.install(); self.objectWillChange.send() }
    }

    // MARK: Bottles

    func createBottle(name: String, engine: Engine) {
        perform("Creating “\(name)” — setting up Windows…") {
            let b = try await Bottle.create(name: name, engine: engine)
            self.refresh()
            self.selection = b.id
        }
    }

    func save(_ bottle: Bottle, previous: BottleConfig) {
        perform("Applying settings…") {
            try bottle.save()
            try await Wine.apply(bottle, previous: previous)
        }
    }

    func delete(_ bottle: Bottle) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(bottle.config.name)”?"
        alert.informativeText = "The bottle and everything installed in it will be moved to the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform("Deleting…") {
            try await bottle.delete()
            if self.selection == bottle.id { self.selection = nil }
        }
    }

    func launch(_ file: URL, in bottle: Bottle) {
        Task {
            do { try await Wine.launch(bottle, file) } catch { self.error = error.localizedDescription }
        }
    }

    func run(_ args: [String], in bottle: Bottle) {
        Task {
            do { try await Wine.run(bottle, args, wait: false) } catch { self.error = error.localizedDescription }
        }
    }

    func stopAll(_ bottle: Bottle) {
        perform("Stopping Windows programs…") { try await Wine.kill(bottle) }
    }

    func pin(_ file: URL, in bottle: Bottle, _ on: Bool = true) {
        var b = bottle
        b.config.pinned.removeAll { $0 == file.path }
        if on { b.config.pinned.append(file.path) }
        do { try b.save(); refresh() } catch { self.error = error.localizedDescription }
    }

    func installStore(_ store: Store, into bottle: Bottle) {
        perform("Installing \(store.name)…") {
            self.progress[store.name] = 0
            defer { self.progress[store.name] = nil }
            _ = try await store.install(into: bottle) { p in Task { @MainActor in self.progress[store.name] = p } }
            self.notice = "\(store.name) is installed. Double-click it in the library to open it."
        }
    }

    func winetricks(_ verb: String, label: String, in bottle: Bottle) {
        perform("Installing \(label)… (this can take a few minutes)") {
            try await Wine.winetricks(bottle, verb)
            self.notice = "\(label) installed."
        }
    }

    private var iconCache: [URL: NSImage?] = [:]

    /// The program's own Windows icon, extracted off the main thread and cached.
    func icon(for program: Program, in bottle: Bottle) async -> NSImage? {
        if let cached = iconCache[program.url] { return cached }
        let url = program.url, driveC = bottle.driveC
        let data = await Task.detached(priority: .utility) { WindowsIcon.ico(for: url, driveC: driveC) }.value
        let image = data.flatMap(NSImage.init(data:))
        iconCache[program.url] = image
        return image
    }

    func addToApplications(_ program: Program, in bottle: Bottle) {
        do {
            let app = try Shortcut.create(for: program, in: bottle, decanter: Bundle.main.executablePath ?? CommandLine.arguments[0])
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch { self.error = error.localizedDescription }
    }

    // MARK: Updates

    func checkForUpdates() {
        Task {
            let api = URL(string: "https://api.github.com/repos/AryanKansagara/Decanter/releases/latest")!
            struct Release: Decodable { let tag_name: String; let html_url: URL }
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            do {
                let (data, _) = try await URLSession.shared.data(from: api)
                let latest = try JSONDecoder().decode(Release.self, from: data)
                let tag = latest.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                if tag.compare(current, options: .numeric) == .orderedDescending {
                    NSWorkspace.shared.open(latest.html_url)
                } else {
                    notice = "Decanter \(current) is the latest version."
                }
            } catch {
                self.error = "Couldn't check for updates: \(error.localizedDescription)"
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
