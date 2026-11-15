import Foundation

/// Everything Decanter stores lives under ~/Library/Application Support/Decanter.
public enum Paths {
    nonisolated(unsafe) public static var root = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Decanter", directoryHint: .isDirectory)
    public static var bottles: URL { root.appending(path: "Bottles", directoryHint: .isDirectory) }
    public static var engines: URL { root.appending(path: "Engines", directoryHint: .isDirectory) }
    public static var logs: URL { root.appending(path: "Logs", directoryHint: .isDirectory) }
}

/// A downloadable runtime piece. Versions are pinned to builds tested with Decanter;
/// bump them here to update.
public struct Component: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let url: URL
    public let megabytes: Int
    public let summary: String
    /// Third-party license the user must accept before download (Apple's D3DMetal).
    public let licenseURL: URL?
}

public enum Catalog {
    public static let gptk = Component(
        id: "gptk", name: "Game Porting Toolkit", version: "3.0-3",
        url: URL(string: "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz")!,
        megabytes: 228,
        summary: "Apple's D3DMetal (DirectX 11/12 → Metal) with its Wine. Best for modern games.",
        licenseURL: URL(string: "https://github.com/user-attachments/files/23971305/License.pdf"))
    public static let wine = Component(
        id: "wine", name: "Wine Staging", version: "11.21",
        url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-staging-11.21-osx64.tar.xz")!,
        megabytes: 218,
        summary: "Current Wine with MoltenVK. Runs DXMT, DXVK and older games.",
        licenseURL: nil)
    public static let dxmt = Component(
        id: "dxmt", name: "DXMT", version: "v0.80",
        url: URL(string: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz")!,
        megabytes: 18,
        summary: "DirectX 10/11 → Metal for Wine bottles.",
        licenseURL: nil)
    public static let dxvk = Component(
        id: "dxvk", name: "DXVK (macOS)", version: "1.10.3-20230507-repack",
        url: URL(string: "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack-builtin.tar.gz")!,
        megabytes: 3,
        summary: "DirectX 10/11 → Vulkan → Metal (MoltenVK) for Wine bottles.",
        licenseURL: nil)
    public static let winetricks = Component(
        id: "winetricks", name: "Winetricks", version: "20260125",
        url: URL(string: "https://raw.githubusercontent.com/Winetricks/winetricks/20260125/src/winetricks")!,
        megabytes: 1,
        summary: "Installs Windows runtimes (Visual C++, .NET, fonts) into bottles.",
        licenseURL: nil)

    public static let all = [gptk, wine, dxmt, dxvk, winetricks]
}

public enum Installer {
    static func marker(_ c: Component) -> URL { Paths.engines.appending(path: ".\(c.id).version") }

    public static func isInstalled(_ c: Component) -> Bool {
        (try? String(contentsOf: marker(c), encoding: .utf8)) == c.version
    }

    /// Downloads, unpacks and records a component, then rebuilds the Wine graphics variants.
    public static func install(_ c: Component, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.engines, withIntermediateDirectories: true)
        let file = try await download(c.url, progress: progress)
        defer { try? fm.removeItem(at: file) }
        let dest = Paths.engines.appending(path: c.id, directoryHint: .isDirectory)
        try? fm.removeItem(at: dest)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        if c.id == "winetricks" {
            let script = dest.appending(path: "winetricks")
            try fm.moveItem(at: file, to: script)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        } else {
            try Shell.run("/usr/bin/tar", ["-xf", file.path, "-C", dest.path])
        }
        try c.version.write(to: marker(c), atomically: true, encoding: .utf8)
        try buildVariants()
    }

    /// DXMT/DXVK ship as Wine "builtin" DLLs, which Wine only loads from its own lib folder.
    /// So each is layered onto an APFS clone of the Wine engine (clones cost ~no disk).
    public static func buildVariants() throws {
        let fm = FileManager.default
        guard isInstalled(Catalog.wine) else { return }
        let base = Paths.engines.appending(path: "wine")
        for layer in [Catalog.dxmt, Catalog.dxvk] where isInstalled(layer) {
            let variant = Paths.engines.appending(path: "wine-\(layer.id)")
            try? fm.removeItem(at: variant)
            try fm.copyItem(at: base, to: variant)
            guard let lib = Engine.wineRoot(in: variant)?.appending(path: "lib/wine"),
                  let src = firstDir(containing: "x86_64-windows", under: Paths.engines.appending(path: layer.id))
            else { throw DecanterError("\(layer.name) or Wine has an unexpected layout") }
            for arch in ["x86_64-windows", "i386-windows", "x86_64-unix"] {
                let from = src.appending(path: arch)
                try fm.createDirectory(at: lib.appending(path: arch), withIntermediateDirectories: true)
                for name in (try? fm.contentsOfDirectory(atPath: from.path)) ?? [] {
                    let to = lib.appending(path: "\(arch)/\(name)")
                    try? fm.removeItem(at: to)
                    try fm.copyItem(at: from.appending(path: name), to: to)
                }
            }
        }
    }

    static func firstDir(containing child: String, under root: URL) -> URL? {
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = e?.nextObject() as? URL {
            if url.lastPathComponent == child { return url.deletingLastPathComponent() }
        }
        return nil
    }

    static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                observation?.invalidate()
                if let error { return cont.resume(throwing: error) }
                guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return cont.resume(throwing: DecanterError("Download failed: \(url.lastPathComponent)"))
                }
                // The temp file is deleted when this handler returns, so move it first.
                let kept = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
                do { try FileManager.default.moveItem(at: tmp, to: kept); cont.resume(returning: kept) }
                catch { cont.resume(throwing: error) }
            }
            observation = task.progress.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
            task.resume()
        }
    }
}

public enum Rosetta {
    /// Every engine is x86_64, so Apple Silicon Macs need Rosetta 2.
    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }

    /// Prompts for an admin password via the standard macOS dialog.
    public static func install() throws {
        try Shell.run("/usr/bin/osascript", ["-e",
            #"do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges"#])
    }
}

public struct DecanterError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

enum Shell {
    /// Runs a tool to completion; throws with its stderr on failure.
    @discardableResult
    static func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw DecanterError("\((path as NSString).lastPathComponent) failed: \(String(decoding: errData, as: UTF8.self))")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
