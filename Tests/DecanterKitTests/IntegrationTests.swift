import AppKit
import Foundation
import Testing
@testable import DecanterKit

/// Real downloads and real Wine. Opt in with `make integration` (~450 MB, a few minutes).
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DECANTER_INTEGRATION"] != nil))
struct IntegrationTests {
    @Test func endToEnd() async throws {
        Paths.root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DECANTER_INTEGRATION_ROOT"]
            ?? NSHomeDirectory() + "/Library/Caches/decanter-integration")

        for c in Catalog.all where !Installer.isInstalled(c) {
            try await Installer.install(c) { _ in }
        }
        for g in Graphics.allCases {
            var c = BottleConfig(name: "x", engine: g == .d3dmetal ? .gptk : .wine)
            c.graphics = g
            #expect(Wine.root(for: c) != nil, "\(g) engine missing")
        }

        for engine in Engine.allCases {
            let b = try await Bottle.create(name: "it-\(engine.rawValue)", engine: engine)
            #expect(try await Wine.run(b, ["cmd", "/c", "ver"]) == 0)
            let mine = b.driveC.appending(path: "windows/system32/winemine.exe")
            #expect(WindowsIcon.ico(for: mine, driveC: b.driveC).flatMap(NSImage.init(data:)) != nil, "winemine icon")
            #expect(try await Wine.run(b, ["reg", "query", #"HKCU\Software\Wine\Mac Driver"#, "/v", "RetinaMode"]) == 0)

            if engine == .gptk {
                try await Wine.winetricks(b, "win10")
                let steam = try await Store.all[0].install(into: b) { _ in }
                #expect(steam.programs().contains { $0.name == "steam" })
                for p in steam.programs() {
                    #expect(WindowsIcon.ico(for: p.url, driveC: b.driveC).flatMap(NSImage.init(data:)) != nil, "\(p.name) icon")
                }
            } else {
                for g in [Graphics.dxmt, .dxvk, .wined3d] {
                    var gb = b
                    gb.config.graphics = g
                    #expect(try await Wine.run(gb, ["cmd", "/c", "ver"]) == 0, "\(g) failed")
                }
            }
            try await Wine.kill(b)
            try FileManager.default.removeItem(at: b.url)
        }
    }
}
