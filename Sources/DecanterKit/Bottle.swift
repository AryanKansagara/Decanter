import Foundation

/// Which Wine build a bottle runs on. Fixed at creation: prefixes don't survive Wine downgrades.
public enum Engine: String, Codable, CaseIterable, Sendable {
    case gptk, wine

    public var label: String { self == .gptk ? "Game Porting Toolkit (D3DMetal)" : "Wine Staging (DXMT / DXVK)" }
    public var graphicsOptions: [Graphics] { self == .gptk ? [.d3dmetal] : [.dxmt, .dxvk, .wined3d] }

    /// `<dir>/<Something>.app/Contents/Resources/wine`, the layout of Gcenx's builds.
    static func wineRoot(in dir: URL) -> URL? {
        let app = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.first { $0.hasSuffix(".app") }
        return app.map { dir.appending(path: "\($0)/Contents/Resources/wine", directoryHint: .isDirectory) }
    }
}

public enum Graphics: String, Codable, CaseIterable, Sendable {
    case d3dmetal, dxmt, dxvk, wined3d

    public var label: String {
        switch self {
        case .d3dmetal: "D3DMetal (DX11/DX12)"
        case .dxmt: "DXMT (DX10/DX11 → Metal)"
        case .dxvk: "DXVK (DX10/DX11 → Vulkan)"
        case .wined3d: "WineD3D (DX1–DX9, OpenGL)"
        }
    }

    /// Engine folder under Paths.engines holding the Wine to launch.
    var engineDir: String {
        switch self {
        case .d3dmetal: "gptk"
        case .dxmt: "wine-dxmt"
        case .dxvk: "wine-dxvk"
        case .wined3d: "wine"
        }
    }
}

public struct BottleConfig: Codable, Hashable, Sendable {
    public var name: String
    public var engine: Engine = .gptk
    public var graphics: Graphics = .d3dmetal
    public var windowsVersion = "win10"
    public var retina = false
    /// Tell Rosetta to report AVX so games that require it start.
    public var avx = true
    /// Event-based sync (GPTK only); cuts CPU overhead in most games.
    public var esync = true
    /// D3DMetal: route DLSS to MetalFX upscaling.
    public var metalFX = false
    /// DXMT: expose NVIDIA extensions (nvapi) so DLSS/Reflex options appear.
    public var nvidiaExtensions = false
    public var debugLog = false
    public var dllOverrides = ""
    public var environment: [String: String] = [:]
    /// Unix paths of programs pinned to the bottle's library.
    public var pinned: [String] = []

    public init(name: String, engine: Engine = .gptk) {
        self.name = name
        self.engine = engine
        graphics = engine.graphicsOptions[0]
    }

    /// Decodes leniently: keys missing from older files fall back to defaults.
    public static func decode(_ data: Data) throws -> BottleConfig {
        guard var merged = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BottleConfig(name: ""))) as? [String: Any],
              let stored = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw DecanterError("Unreadable bottle settings") }
        merged.merge(stored) { $1 }
        return try JSONDecoder().decode(BottleConfig.self, from: JSONSerialization.data(withJSONObject: merged))
    }
}

/// A bottle is a Wine prefix folder plus `decanter.json`.
public struct Bottle: Identifiable, Hashable, Sendable {
    public let url: URL
    public var config: BottleConfig
    public var id: URL { url }
    public var driveC: URL { url.appending(path: "drive_c", directoryHint: .isDirectory) }
    var configFile: URL { url.appending(path: "decanter.json") }

    public init(url: URL, config: BottleConfig) {
        self.url = url
        self.config = config
    }

    public func save() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(config).write(to: configFile, options: .atomic)
    }

    public static func all() -> [Bottle] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Paths.bottles, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            (try? Data(contentsOf: dir.appending(path: "decanter.json")))
                .flatMap { try? BottleConfig.decode($0) }
                .map { Bottle(url: dir, config: $0) }
        }.sorted { $0.config.name.localizedStandardCompare($1.config.name) == .orderedAscending }
    }

    /// Creates the folder and initializes the Windows environment (takes ~15 s).
    public static func create(name: String, engine: Engine) async throws -> Bottle {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.bottles, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        var dir = Paths.bottles.appending(path: safe.isEmpty ? "Bottle" : safe, directoryHint: .isDirectory)
        var n = 2
        while fm.fileExists(atPath: dir.path) {
            dir = Paths.bottles.appending(path: "\(safe) \(n)", directoryHint: .isDirectory)
            n += 1
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let bottle = Bottle(url: dir, config: BottleConfig(name: name, engine: engine))
        try bottle.save()
        do {
            try await Wine.run(bottle, ["wineboot", "--init"])
            try await Wine.apply(bottle, previous: nil)
        } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
        return bottle
    }

    public func delete() async throws {
        try? await Wine.kill(self)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
