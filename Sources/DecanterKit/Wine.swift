import Foundation

public enum Wine {
    /// The Wine install a bottle launches with, or nil if its components aren't installed.
    public static func root(for config: BottleConfig) -> URL? {
        let dir = Paths.engines.appending(path: config.graphics.engineDir, directoryHint: .isDirectory)
        return Engine.wineRoot(in: dir).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    static func binary(_ root: URL, _ engine: Engine) -> URL {
        root.appending(path: engine == .gptk ? "bin/wine64" : "bin/wine")
    }

    /// Variables layered over the user's environment for every Wine process in a bottle.
    public static func environment(for bottle: Bottle, base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        let c = bottle.config
        var env = base
        env["WINEPREFIX"] = bottle.url.path
        env["WINEDEBUG"] = c.debugLog ? "+seh,+loaddll,warn+all" : "-all"
        // Stops Wine scattering .desktop/menu junk; users get Mac shortcuts from Decanter instead.
        env["WINEDLLOVERRIDES"] = (["winemenubuilder.exe=d"] + [c.dllOverrides].filter { !$0.isEmpty }).joined(separator: ";")
        // .NET 7+ crashes under Rosetta with W^X enabled.
        env["DOTNET_EnableWriteXorExecute"] = "0"
        // Rosetta treats any value as "on", so the only way to disable is to unset it.
        if c.avx { env["ROSETTA_ADVERTISE_AVX"] = "1" } else { env["ROSETTA_ADVERTISE_AVX"] = nil }
        if c.engine == .gptk {
            if c.esync { env["WINEESYNC"] = "1" }
            if c.metalFX { env["D3DM_ENABLE_METALFX"] = "1" }
        }
        if c.graphics == .dxmt, c.nvidiaExtensions { env["DXMT_ENABLE_NVEXT"] = "1" }
        if c.graphics == .dxvk { env["DXVK_ASYNC"] = "1" }
        env.merge(c.environment) { $1 }
        return env
    }

    public static func logFile(_ bottle: Bottle) -> URL {
        Paths.logs.appending(path: "\(bottle.url.lastPathComponent).log")
    }

    /// Starts `wine <args>` in the bottle. Awaits exit when `wait`, otherwise returns once launched.
    @discardableResult
    public static func run(_ bottle: Bottle, _ args: [String], cwd: URL? = nil, extraEnv: [String: String] = [:],
                           executable: URL? = nil, wait: Bool = true) async throws -> Int32 {
        guard let root = root(for: bottle.config) else {
            throw DecanterError("Install \(bottle.config.graphics.label) components first (Decanter → Components).")
        }
        let p = Process()
        p.executableURL = executable ?? binary(root, bottle.config.engine)
        p.arguments = args
        p.environment = environment(for: bottle).merging(extraEnv) { $1 }
        // drive_c doesn't exist until wineboot has run.
        p.currentDirectoryURL = cwd ?? (FileManager.default.fileExists(atPath: bottle.driveC.path) ? bottle.driveC : bottle.url)
        let log = try openLog(bottle, header: ([p.executableURL!.lastPathComponent] + args).joined(separator: " "))
        p.standardOutput = log
        p.standardError = log
        p.standardInput = FileHandle.nullDevice
        if !wait {
            try p.run()
            return 0
        }
        return try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    /// Opens an .exe/.msi/.lnk/.bat the way Windows would. Executables run from their own folder,
    /// which many games require to find their data.
    public static func launch(_ bottle: Bottle, _ file: URL, arguments: [String] = []) async throws {
        switch file.pathExtension.lowercased() {
        case "exe":
            try await run(bottle, [file.path] + arguments, cwd: file.deletingLastPathComponent(), wait: false)
        case "msi":
            try await run(bottle, ["msiexec", "/i", file.path] + arguments, wait: false)
        default:
            try await run(bottle, ["start", "/unix", file.path] + arguments, wait: false)
        }
    }

    /// Ends every Windows process in the bottle.
    public static func kill(_ bottle: Bottle) async throws {
        guard let root = root(for: bottle.config) else { return }
        try await run(bottle, ["-k"], executable: root.appending(path: "bin/wineserver"))
    }

    /// Writes settings that live in the Windows registry. `previous == nil` applies everything.
    public static func apply(_ bottle: Bottle, previous: BottleConfig?) async throws {
        let c = bottle.config
        if previous?.windowsVersion != c.windowsVersion {
            try await run(bottle, ["winecfg", "-v", c.windowsVersion])
        }
        if previous?.retina != c.retina {
            try await run(bottle, ["reg", "add", #"HKCU\Software\Wine\Mac Driver"#, "/v", "RetinaMode",
                                   "/t", "REG_SZ", "/d", c.retina ? "y" : "n", "/f"])
        }
    }

    /// Runs a Winetricks verb (e.g. `vcrun2022`) unattended.
    public static func winetricks(_ bottle: Bottle, _ verb: String) async throws {
        guard let root = root(for: bottle.config) else { throw DecanterError("Engine not installed") }
        let script = Paths.engines.appending(path: "winetricks/winetricks")
        guard Installer.isInstalled(Catalog.winetricks) else { throw DecanterError("Install Winetricks first (Components).") }
        let status = try await run(bottle, ["-q", verb], extraEnv: [
            "WINE": binary(root, bottle.config.engine).path,
            "WINESERVER": root.appending(path: "bin/wineserver").path,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        ], executable: script)
        if status != 0 { throw DecanterError("Winetricks \(verb) failed (exit \(status)). See the bottle log.") }
    }

    static func openLog(_ bottle: Bottle, header: String) throws -> FileHandle {
        let url = logFile(bottle)
        try FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let h = try FileHandle(forWritingTo: url)
        if h.seekToEndOfFile() > 5_000_000 { h.truncateFile(atOffset: 0) } // keep logs bounded
        h.write(Data("\n=== \(Date().formatted()) — \(header)\n".utf8))
        return h
    }
}
