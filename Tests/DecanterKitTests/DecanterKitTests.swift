import Foundation
import Testing
@testable import DecanterKit

@Suite(.serialized) struct DecanterKitTests {
    init() throws {
        Paths.root = FileManager.default.temporaryDirectory.appending(path: "decanter-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: Paths.bottles, withIntermediateDirectories: true)
    }

    func makeBottle(_ config: BottleConfig) throws -> Bottle {
        let dir = Paths.bottles.appending(path: config.name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let b = Bottle(url: dir, config: config)
        try b.save()
        return b
    }

    @Test func oldSettingsFilesGetDefaults() throws {
        let c = try BottleConfig.decode(Data(#"{"name":"Old","engine":"wine","graphics":"dxvk"}"#.utf8))
        #expect(c.name == "Old" && c.graphics == .dxvk && c.avx && c.windowsVersion == "win10")
    }

    @Test func gptkEnvironment() throws {
        var c = BottleConfig(name: "G")
        c.metalFX = true
        c.dllOverrides = "dinput8=n,b"
        c.environment = ["WINEDEBUG": "+fps"]
        let env = Wine.environment(for: try makeBottle(c), base: ["ROSETTA_ADVERTISE_AVX": "0"])
        #expect(c.graphics == .d3dmetal)
        #expect(env["WINEESYNC"] == "1" && env["D3DM_ENABLE_METALFX"] == "1")
        #expect(env["WINEDLLOVERRIDES"] == "winemenubuilder.exe=d;dinput8=n,b")
        #expect(env["WINEDEBUG"] == "+fps") // user variables win
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "1")
        #expect(env["WINEPREFIX"]?.hasSuffix("/G") == true)
    }

    @Test func wineEnvironmentHonorsToggles() throws {
        var c = BottleConfig(name: "W", engine: .wine)
        c.avx = false
        c.nvidiaExtensions = true
        let env = Wine.environment(for: try makeBottle(c), base: ["ROSETTA_ADVERTISE_AVX": "1"])
        #expect(c.graphics == .dxmt)
        #expect(env["ROSETTA_ADVERTISE_AVX"] == nil) // Rosetta needs it unset, not "0"
        #expect(env["WINEESYNC"] == nil && env["DXMT_ENABLE_NVEXT"] == "1")
    }

    @Test func bottlesRoundTripAndSort() throws {
        _ = try makeBottle(BottleConfig(name: "b"))
        _ = try makeBottle(BottleConfig(name: "A"))
        #expect(Bottle.all().map(\.config.name) == ["A", "b"])
    }

    @Test func programDiscovery() throws {
        var c = BottleConfig(name: "P")
        let b0 = try makeBottle(c)
        let menu = b0.driveC.appending(path: "users/me/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Game")
        try FileManager.default.createDirectory(at: menu, withIntermediateDirectories: true)
        for f in ["Game.lnk", "Uninstall Game.lnk", "readme.txt", "tool.lnk"] {
            FileManager.default.createFile(atPath: menu.appending(path: f).path, contents: nil)
        }
        let exe = b0.driveC.appending(path: "Tool.exe")
        FileManager.default.createFile(atPath: exe.path, contents: nil)
        c.pinned = [exe.path, "/missing.exe"]
        let b = Bottle(url: b0.url, config: c)
        #expect(b.programs().map(\.name) == ["Tool", "Game"])
    }

    @Test func shortcutTargetsResolveIntoTheBottle() throws {
        // Minimal shell link: header with HasLinkInfo, LinkInfo whose LocalBasePath is a C: path.
        var lnk = Data(count: 0x4C)
        lnk[0] = 0x4C
        lnk[0x14] = 0x02
        var info = Data(count: 0x1C)
        info[16] = 0x1C  // LocalBasePathOffset
        info.append(Data(#"C:\Program Files\Game\game.exe"#.utf8) + [0])
        lnk.append(info)
        let file = Paths.root.appending(path: "Game.lnk")
        try lnk.write(to: file)
        let driveC = Paths.root.appending(path: "drive_c")
        #expect(WindowsIcon.lnkTarget(file, driveC: driveC)?.path == driveC.path + "/Program Files/Game/game.exe")
        #expect(WindowsIcon.ico(for: file, driveC: driveC) == nil) // target missing → no icon, no crash
    }

    @Test func graphicsVariantsLayerDLLs() throws {
        let fm = FileManager.default
        func touch(_ url: URL, _ text: String) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let wineLib = Paths.engines.appending(path: "wine/Wine Staging.app/Contents/Resources/wine/lib/wine")
        try touch(wineLib.appending(path: "x86_64-windows/d3d11.dll"), "wine")
        try touch(Paths.engines.appending(path: "dxmt/v1/x86_64-windows/d3d11.dll"), "dxmt")
        try touch(Paths.engines.appending(path: "dxmt/v1/x86_64-unix/winemetal.so"), "so")
        for c in [Catalog.wine, Catalog.dxmt] { try c.version.write(to: Installer.marker(c), atomically: true, encoding: .utf8) }

        try Installer.buildVariants()

        var cfg = BottleConfig(name: "V", engine: .wine)
        let root = try #require(Wine.root(for: cfg))
        #expect(try String(contentsOf: root.appending(path: "lib/wine/x86_64-windows/d3d11.dll"), encoding: .utf8) == "dxmt")
        #expect(fm.fileExists(atPath: root.appending(path: "lib/wine/x86_64-unix/winemetal.so").path))
        #expect(try String(contentsOf: wineLib.appending(path: "x86_64-windows/d3d11.dll"), encoding: .utf8) == "wine")
        cfg.graphics = .dxvk
        #expect(Wine.root(for: cfg) == nil) // DXVK not installed
    }

    @Test func shortcutScriptQuotesPaths() throws {
        Shortcut.folderOverride = Paths.root.appending(path: "Apps")
        let b = try makeBottle(BottleConfig(name: "It's"))
        let p = Program(name: "Game", url: b.driveC.appending(path: "Game.exe"), pinned: true)
        let app = try Shortcut.create(for: p, in: b, decanter: "/Applications/Decanter.app/Contents/MacOS/Decanter")
        let script = try String(contentsOf: app.appending(path: "Contents/MacOS/launch"), encoding: .utf8)
        #expect(script.contains(#"'/Applications/Decanter.app/Contents/MacOS/Decanter' --run "#))
        #expect(script.contains(#"It'\''s"#))
    }
}
