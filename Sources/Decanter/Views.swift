import DecanterKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.setupDone && model.hasEngine { LibraryView() } else { WelcomeView() }
        }
        .safeAreaInset(edge: .bottom) {
            if let busy = model.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(busy).lineLimit(1)
                    if let p = model.progress.values.first, p > 0, p < 1 {
                        ProgressView(value: p).frame(width: 140)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 10)
            }
        }
        .alert("Something went wrong", isPresented: .init(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") {}
        } message: { Text(model.error ?? "") }
        .alert("Done", isPresented: .init(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") {}
        } message: { Text(model.notice ?? "") }
        .sheet(item: $model.openRequest) { OpenWithSheet(file: $0) }
        .sheet(isPresented: $model.showNewBottle) { NewBottleSheet() }
    }
}

// MARK: - First run

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "wineglass.fill").font(.system(size: 40)).foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text("Welcome to Decanter").font(.largeTitle.bold())
                    Text("Run Windows games and apps on your Mac. First, download the pieces that make it work.")
                        .foregroundStyle(.secondary)
                }
            }
            ComponentsView()
            HStack {
                Spacer()
                Button("Get Started") { model.setupDone = true }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(!model.hasEngine || !model.rosetta || model.busy != nil)
            }
        }
        .padding(28)
    }
}

struct ComponentsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("acceptedAppleLicense") private var acceptedApple = false

    var missing: [Component] {
        Catalog.all.filter { !model.installed.contains($0.id) && ($0.licenseURL == nil || acceptedApple) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                HStack {
                    Image(systemName: "cpu").frame(width: 24)
                    VStack(alignment: .leading) {
                        Text("Rosetta 2").bold()
                        Text("Translates the Intel-based Windows layer for Apple Silicon.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.rosetta { Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    else { Button("Install") { model.installRosetta() } }
                }
                ForEach(Catalog.all) { c in
                    HStack(alignment: .top) {
                        Image(systemName: icon(c)).frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(c.name) ").bold() + Text(c.version).foregroundStyle(.secondary)
                            Text(c.summary).font(.caption).foregroundStyle(.secondary)
                            if let license = c.licenseURL, !model.installed.contains(c.id) {
                                Toggle(isOn: $acceptedApple) {
                                    Text("I accept [Apple's D3DMetal license](\(license.absoluteString))").font(.caption)
                                }
                                .toggleStyle(.checkbox)
                                        }
                        }
                        Spacer()
                        if let p = model.progress[c.id] {
                            ProgressView(value: p).frame(width: 90)
                        } else if model.installed.contains(c.id) {
                            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("\(c.megabytes) MB") { model.install([c]) }
                                .disabled(model.busy != nil || (c.licenseURL != nil && !acceptedApple))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            HStack {
                Text("Downloaded from the projects' official GitHub releases into \((Paths.root.path as NSString).abbreviatingWithTildeInPath).")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Install All") { model.install(missing) }
                    .disabled(missing.isEmpty || model.busy != nil)
            }
        }
    }

    func icon(_ c: Component) -> String {
        ["gptk": "apple.logo", "wine": "wineglass", "dxmt": "cube", "dxvk": "cube.transparent", "winetricks": "wand.and.stars"][c.id] ?? "shippingbox"
    }
}

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Bottles") {
                    ForEach(model.bottles) { b in
                        Label(b.config.name, systemImage: b.config.engine == .gptk ? "wineglass.fill" : "wineglass")
                            .tag(b.id)
                            .contextMenu {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([b.url]) }
                                Button("Delete…", role: .destructive) { model.delete(b) }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .toolbar {
                Button { model.showNewBottle = true } label: { Label("New Bottle", systemImage: "plus") }
            }
        } detail: {
            if let b = model.selected {
                BottleView(bottle: b).id(b.id)
            } else {
                ContentUnavailableView {
                    Label("No Bottles", systemImage: "wineglass")
                } description: {
                    Text("A bottle is a self-contained Windows environment. Create one, then install a game store or run a Windows installer in it.")
                } actions: {
                    Button("New Bottle…") { model.showNewBottle = true }
                }
            }
        }
    }
}

struct BottleView: View {
    @EnvironmentObject var model: AppModel
    let bottle: Bottle
    @State private var showSettings = false
    @State private var showLog = false
    @State private var dropTargeted = false

    var programs: [Program] { bottle.programs() }

    var body: some View {
        Group {
            if programs.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Installed Yet", systemImage: "square.and.arrow.down")
                } description: {
                    Text("Install a game store from **Install**, or drop a Windows installer (.exe or .msi) here.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 18)], spacing: 18) {
                        ForEach(programs) { ProgramTile(program: $0, bottle: bottle) }
                    }
                    .padding(20)
                }
            }
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 12).stroke(.tint, lineWidth: 3).padding(6) } }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.launch(url, in: bottle) } }
            }
            return true
        }
        .navigationTitle(bottle.config.name)
        .navigationSubtitle(bottle.config.graphics.label)
        .toolbar { toolbar }
        .sheet(isPresented: $showSettings) { BottleSettingsSheet(bottle: bottle) }
        .sheet(isPresented: $showLog) { LogSheet(bottle: bottle) }
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button("Run Windows Program…") { if let f = pick() { model.launch(f, in: bottle) } }
                Button("Add Program to Library…") { if let f = pick(in: bottle.driveC) { model.pin(f, in: bottle) } }
            } label: { Label("Run", systemImage: "play.fill") }

            Menu {
                Section("Game Stores") {
                    ForEach(Store.all) { s in Button(s.name) { model.installStore(s, into: bottle) } }
                }
                Section("Windows Runtimes") {
                    ForEach(Runtimes.common, id: \.verb) { r in
                        Button(r.label) { model.winetricks(r.verb, label: r.label, in: bottle) }
                    }
                }
            } label: { Label("Install", systemImage: "square.and.arrow.down") }
            .disabled(model.busy != nil)

            Menu {
                Button("Open C: Drive") { NSWorkspace.shared.open(bottle.driveC) }
                Button("Wine Configuration") { model.run(["winecfg"], in: bottle) }
                Button("Registry Editor") { model.run(["regedit"], in: bottle) }
                Button("Task Manager") { model.run(["taskmgr"], in: bottle) }
                Button("Command Prompt") { model.run(["wineconsole", "cmd"], in: bottle) }
                Button("Uninstall Programs") { model.run(["uninstaller"], in: bottle) }
                Divider()
                Button("Show Log") { showLog = true }
                Button("Stop All Programs") { model.stopAll(bottle) }
            } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }

            Button { showSettings = true } label: { Label("Bottle Settings", systemImage: "slider.horizontal.3") }
        }
    }

    func pick(in dir: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["exe", "msi", "lnk", "bat"].compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = dir
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct ProgramTile: View {
    @EnvironmentObject var model: AppModel
    let program: Program
    let bottle: Bottle
    @State private var hovering = false
    @State private var icon: NSImage?

    var body: some View {
        Button { model.launch(program.url, in: bottle) } label: {
            VStack(spacing: 8) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 52, height: 52)
                    } else {
                        Image(systemName: program.pinned ? "gamecontroller.fill" : "app.fill")
                            .font(.system(size: 34)).foregroundStyle(.tint)
                    }
                }
                    .frame(width: 72, height: 72)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                Text(program.name).font(.callout).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(width: 130, height: 130)
            .background(hovering ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .task(id: program.url) { icon = await model.icon(for: program, in: bottle) }
        .help(program.url.path)
        .contextMenu {
            Button("Open") { model.launch(program.url, in: bottle) }
            Button("Add to Applications") { model.addToApplications(program, in: bottle) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([program.url]) }
            if program.pinned {
                Divider()
                Button("Remove from Library") { model.pin(program.url, in: bottle, false) }
            }
        }
    }
}
