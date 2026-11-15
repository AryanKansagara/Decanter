import DecanterKit
import SwiftUI

struct NewBottleSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Games"
    @State private var engine: Engine = .gptk

    var available: [Engine] { Engine.allCases.filter { model.installed.contains($0.rawValue) } }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Engine", selection: $engine) {
                ForEach(Engine.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Text(engine == .gptk
                 ? "Best for modern DirectX 11/12 games. Uses Apple's D3DMetal."
                 : "Best for DirectX 9–11 games and apps. Switch between DXMT, DXVK and WineD3D per bottle.")
                .font(.caption).foregroundStyle(.secondary)
            if !available.contains(engine) {
                Text("Install \(engine == .gptk ? "Game Porting Toolkit" : "Wine Staging") in Settings → Components first.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { model.createBottle(name: name, engine: engine); dismiss() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !available.contains(engine))
            }
        }
        .onAppear { if let first = available.first { engine = first } }
    }
}

struct BottleSettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle
    @State private var config: BottleConfig
    @State private var envText: String

    init(bottle: Bottle) {
        self.bottle = bottle
        _config = State(initialValue: bottle.config)
        _envText = State(initialValue: bottle.config.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
    }

    static let windowsVersions = [("win11", "Windows 11"), ("win10", "Windows 10"), ("win81", "Windows 8.1"), ("win7", "Windows 7"), ("winxp64", "Windows XP")]

    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $config.name)
                Picker("Windows version", selection: $config.windowsVersion) {
                    ForEach(Self.windowsVersions, id: \.0) { Text($0.1).tag($0.0) }
                }
                LabeledContent("Engine", value: config.engine.label)
            }
            Section("Graphics") {
                Picker("Renderer", selection: $config.graphics) {
                    ForEach(config.engine.graphicsOptions, id: \.self) { g in
                        Text(g.label + (Wine.root(for: with(g)) == nil ? " — not installed" : "")).tag(g)
                    }
                }
                Toggle("High resolution (Retina) mode", isOn: $config.retina)
                if config.engine == .gptk {
                    Toggle("DLSS → MetalFX upscaling", isOn: $config.metalFX)
                }
                if config.graphics == .dxmt {
                    Toggle("Expose NVIDIA extensions (DLSS, Reflex)", isOn: $config.nvidiaExtensions)
                }
            }
            Section("Performance") {
                Toggle("Advertise AVX to games", isOn: $config.avx)
                if config.engine == .gptk {
                    Toggle("ESync (faster thread sync)", isOn: $config.esync)
                }
            }
            Section("Advanced") {
                TextField("DLL overrides", text: $config.dllOverrides, prompt: Text("e.g. dinput8=n,b;xinput1_3=n,b"))
                VStack(alignment: .leading) {
                    Text("Environment variables (one KEY=value per line)")
                    TextEditor(text: $envText).font(.body.monospaced()).frame(height: 70)
                }
                Toggle("Detailed debug log", isOn: $config.debugLog)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var b = bottle
                    b.config = config
                    b.config.environment = parseEnv(envText)
                    model.save(b, previous: bottle.config)
                    dismiss()
                }
            }
        }
    }

    func with(_ g: Graphics) -> BottleConfig { var c = config; c.graphics = g; return c }

    func parseEnv(_ text: String) -> [String: String] {
        var env: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty { env[parts[0]] = parts[1] }
        }
        return env
    }
}

struct LogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(text.isEmpty ? "No output yet." : text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .defaultScrollAnchor(.bottom)
            Divider()
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Wine.logFile(bottle)]) }
                Button("Clear") { try? Data().write(to: Wine.logFile(bottle)); load() }
                Button("Refresh", action: load)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 760, height: 520)
        .onAppear(perform: load)
    }

    func load() {
        // Tail only: logs from chatty games can reach megabytes.
        guard let h = try? FileHandle(forReadingFrom: Wine.logFile(bottle)) else { return text = "" }
        let size = h.seekToEndOfFile()
        h.seek(toFileOffset: size > 200_000 ? size - 200_000 : 0)
        text = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
    }
}

/// Shown when a Windows file is opened with Decanter from Finder.
struct OpenWithSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let file: URL
    @State private var bottle: URL?
    @State private var addToLibrary = false

    var body: some View {
        Form {
            Text("Open “\(file.lastPathComponent)” in:").font(.headline)
            if model.bottles.isEmpty {
                Text("Create a bottle first.").foregroundStyle(.secondary)
            } else {
                Picker("Bottle", selection: $bottle) {
                    ForEach(model.bottles) { Text($0.config.name).tag(Optional($0.id)) }
                }
                if file.pathExtension.lowercased() == "exe" {
                    Toggle("Add to the bottle's library", isOn: $addToLibrary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Open") {
                    if let b = model.bottles.first(where: { $0.id == bottle }) {
                        if addToLibrary { model.pin(file, in: b) }
                        model.launch(file, in: b)
                        model.selection = b.id
                    }
                    dismiss()
                }
                .disabled(bottle == nil)
            }
        }
        .onAppear { bottle = model.selection ?? model.bottles.first?.id }
    }
}
