import AppKit
import DecanterKit
import SwiftUI

// `Decanter --run <bottle> <file>` is what the ~/Applications/Decanter shortcuts call:
// launch the program and exit without showing any UI.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--run"), args.count > i + 2 {
    guard let bottle = Bottle.load(URL(fileURLWithPath: args[i + 1])) else {
        fputs("No bottle at \(args[i + 1])\n", stderr)
        exit(1)
    }
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var status: Int32 = 0
    Task {
        do { try await Wine.launch(bottle, URL(fileURLWithPath: args[i + 2])) } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            status = 1
        }
        done.signal()
    }
    done.wait()
    exit(status)
}
DecanterApp.main()

struct DecanterApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Decanter") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Bottle…") { model.showNewBottle = true }.keyboardShortcut("n")
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { model.checkForUpdates() }
            }
        }
        Settings {
            ComponentsView().environmentObject(model).padding().frame(width: 620, height: 520)
        }
    }
}

/// Finder "Open With → Decanter" on .exe/.msi/.lnk/.bat files.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in AppModel.shared.openRequest = urls.first }
    }
}
