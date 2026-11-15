import Foundation

public struct Program: Identifiable, Hashable, Sendable {
    public let name: String
    public let url: URL
    public let pinned: Bool
    public var id: URL { url }
}

extension Bottle {
    /// Pinned programs first, then Start Menu shortcuts installers created.
    public func programs() -> [Program] {
        let fm = FileManager.default
        let pinned = config.pinned.map { URL(fileURLWithPath: $0) }
            .filter { fm.fileExists(atPath: $0.path) }
            .map { Program(name: $0.deletingPathExtension().lastPathComponent, url: $0, pinned: true) }
        let users = (try? fm.contentsOfDirectory(atPath: driveC.appending(path: "users").path)) ?? []
        let menus = [driveC.appending(path: "ProgramData/Microsoft/Windows/Start Menu")]
            + users.map { driveC.appending(path: "users/\($0)/AppData/Roaming/Microsoft/Windows/Start Menu") }
        var seen = Set(pinned.map(\.name))
        var found: [Program] = []
        for menu in menus {
            let e = fm.enumerator(at: menu, includingPropertiesForKeys: nil)
            while let url = e?.nextObject() as? URL {
                let name = url.deletingPathExtension().lastPathComponent
                guard url.pathExtension.lowercased() == "lnk",
                      !name.localizedCaseInsensitiveContains("uninstall"),
                      seen.insert(name).inserted else { continue }
                found.append(Program(name: name, url: url, pinned: false))
            }
        }
        return pinned + found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// One-click installers for game stores.
public struct Store: Identifiable, Sendable {
    public let name: String
    public let installer: URL
    /// Installer flags; empty means the installer shows its own wizard.
    public let flags: [String]
    /// Main program, relative to drive_c, pinned after install.
    public let program: String
    public var id: String { name }

    public static let all = [
        Store(name: "Steam",
              installer: URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!,
              flags: ["/S"], program: "Program Files (x86)/Steam/steam.exe"),
        Store(name: "Epic Games Launcher",
              installer: URL(string: "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi")!,
              flags: ["/qn"], program: "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"),
        Store(name: "GOG Galaxy",
              installer: URL(string: "https://webinstallers.gog-statics.com/download/GOG_Galaxy_2.0.exe")!,
              flags: [], program: "Program Files (x86)/GOG Galaxy/GalaxyClient.exe"),
        Store(name: "Battle.net",
              installer: URL(string: "https://downloader.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP&version=Live")!,
              flags: [], program: "Program Files (x86)/Battle.net/Battle.net Launcher.exe"),
        Store(name: "EA app",
              installer: URL(string: "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe")!,
              flags: [], program: "Program Files/Electronic Arts/EA Desktop/EA Desktop/EALauncher.exe"),
        Store(name: "Ubisoft Connect",
              installer: URL(string: "https://ubi.li/4vxt9")!,
              flags: ["/S"], program: "Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe"),
    ]

    /// Downloads and runs the installer, then pins the store's launcher. Returns the updated bottle.
    public func install(into bottle: Bottle, progress: @escaping @Sendable (Double) -> Void) async throws -> Bottle {
        let file = try await Installer.download(installer, progress: progress)
        let named = file.deletingLastPathComponent()
            .appending(path: name.replacingOccurrences(of: " ", with: "") + (installer.path.hasSuffix(".msi") ? ".msi" : ".exe"))
        try? FileManager.default.removeItem(at: named)
        try FileManager.default.moveItem(at: file, to: named)
        defer { try? FileManager.default.removeItem(at: named) }
        let args = named.pathExtension == "msi" ? ["msiexec", "/i", named.path] + flags : [named.path] + flags
        try await Wine.run(bottle, args)
        var b = bottle
        let exe = bottle.driveC.appending(path: program)
        guard FileManager.default.fileExists(atPath: exe.path) else {
            throw DecanterError("\(name) installer finished but \(exe.lastPathComponent) wasn't found. Check the bottle log.")
        }
        if !b.config.pinned.contains(exe.path) { b.config.pinned.append(exe.path) }
        try b.save()
        return b
    }
}

/// Curated Winetricks verbs games commonly need.
public enum Runtimes {
    public static let common: [(verb: String, label: String)] = [
        ("vcrun2022", "Visual C++ 2015–2022"),
        ("dotnet48", ".NET Framework 4.8"),
        ("dotnetdesktop8", ".NET Desktop Runtime 8"),
        ("d3dcompiler_47", "D3DCompiler 47"),
        ("d3dx9", "DirectX 9 (d3dx9)"),
        ("xact", "XACT audio"),
        ("physx", "NVIDIA PhysX"),
        ("corefonts", "Microsoft core fonts"),
    ]
}

public enum Shortcut {
    nonisolated(unsafe) static var folderOverride: URL?
    public static var folder: URL {
        folderOverride ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/Decanter", directoryHint: .isDirectory)
    }

    /// Writes a tiny .app to ~/Applications/Decanter that opens `program` through Decanter,
    /// so games show up in Launchpad, Spotlight and the Dock.
    @discardableResult
    public static func create(for program: Program, in bottle: Bottle, decanter: String) throws -> URL {
        let app = folder.appending(path: "\(program.name).app", directoryHint: .isDirectory)
        let macos = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: app)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        exec \(quote(decanter)) --run \(quote(bottle.url.path)) \(quote(program.url.path))

        """
        try script.write(to: macos.appending(path: "launch"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macos.appending(path: "launch").path)
        let plist: [String: Any] = [
            "CFBundleExecutable": "launch",
            "CFBundleName": program.name,
            "CFBundleIdentifier": "app.decanter.shortcut." + program.name.filter { $0.isLetter || $0.isNumber },
            "CFBundlePackageType": "APPL",
            "LSUIElement": true,
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))
        return app
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }
}
