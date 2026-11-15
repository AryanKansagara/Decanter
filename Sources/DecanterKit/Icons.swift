import Foundation

/// Pulls icons out of Windows programs so the library shows real artwork.
public enum WindowsIcon {
    /// `.ico` bytes for an `.exe` (its first icon group) or a `.lnk` (its target's), or nil.
    public static func ico(for url: URL, driveC: URL) -> Data? {
        switch url.pathExtension.lowercased() {
        case "exe": return fromPE(url)
        case "lnk": return lnkTarget(url, driveC: driveC).flatMap { fromPE($0) }
        default: return nil
        }
    }

    /// Resolves a shell link's LocalBasePath (e.g. `C:\Games\x.exe`) inside the bottle.
    static func lnkTarget(_ url: URL, driveC: URL) -> URL? {
        guard let d = try? Data(contentsOf: url), d.count > 0x4C, d.u32(0) == 0x4C else { return nil }
        let flags = d.u32(0x14)
        var at = 0x4C
        if flags & 0x1 != 0 { at += 2 + Int(d.u16(at)) }  // skip LinkTargetIDList
        guard flags & 0x2 != 0, at + 28 <= d.count else { return nil }  // needs LinkInfo
        let base = at + Int(d.u32(at + 16))
        guard base < d.count, let end = d[base...].firstIndex(of: 0),
              let path = String(data: d[base..<end], encoding: .windowsCP1252),
              path.uppercased().hasPrefix("C:\\") else { return nil }
        return driveC.appending(path: path.dropFirst(3).replacingOccurrences(of: "\\", with: "/"))
    }

    static func fromPE(_ url: URL) -> Data? {
        // Memory-mapped: game executables can be gigabytes and we touch only a few pages.
        guard let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count > 0x40, d.u16(0) == 0x5A4D else { return nil }
        let pe = Int(d.u32(0x3C))
        guard pe + 24 < d.count, d.u32(pe) == 0x4550 else { return nil }
        let sections = Int(d.u16(pe + 6)), optSize = Int(d.u16(pe + 20)), opt = pe + 24
        let dirs = opt + (d.u16(opt) == 0x20B ? 112 : 96)  // PE32+ vs PE32
        guard dirs + 24 <= d.count else { return nil }
        let rsrcRVA = d.u32(dirs + 16)  // data directory #2: resources
        guard rsrcRVA != 0 else { return nil }

        func offset(_ rva: UInt32) -> Int? {
            for i in 0..<sections {
                let s = opt + optSize + i * 40
                guard s + 40 <= d.count else { return nil }
                let va = d.u32(s + 12), size = max(d.u32(s + 8), d.u32(s + 16))
                if rva >= va && rva < va + size { return Int(d.u32(s + 20) + (rva - va)) }
            }
            return nil
        }
        guard let root = offset(rsrcRVA) else { return nil }

        /// Entries of a resource directory: (id, offset relative to root, isDirectory).
        func entries(_ dir: Int) -> [(id: UInt32, off: Int, isDir: Bool)] {
            guard dir + 16 <= d.count else { return [] }
            let n = Int(d.u16(dir + 12)) + Int(d.u16(dir + 14))
            return (0..<n).compactMap { i in
                let e = dir + 16 + i * 8
                guard e + 8 <= d.count else { return nil }
                let v = d.u32(e + 4)
                return (d.u32(e), Int(v & 0x7FFF_FFFF), v & 0x8000_0000 != 0)
            }
        }
        /// Follows the first entry down to a data blob.
        func leaf(_ entry: (id: UInt32, off: Int, isDir: Bool)) -> Data? {
            var e = entry
            while e.isDir { guard let next = entries(root + e.off).first else { return nil }; e = next }
            let de = root + e.off
            guard de + 8 <= d.count, let o = offset(d.u32(de)) else { return nil }
            let size = Int(d.u32(de + 4))
            return o + size <= d.count ? d.subdata(in: o..<o + size) : nil
        }

        let types = entries(root)
        guard let groupType = types.first(where: { $0.id == 14 && $0.isDir }),  // RT_GROUP_ICON
              let iconType = types.first(where: { $0.id == 3 && $0.isDir }),    // RT_ICON
              let group = entries(root + groupType.off).first.flatMap(leaf), group.count >= 6 else { return nil }
        let icons = entries(root + iconType.off)

        // GRPICONDIR → ICO: same 6-byte header; 14-byte entries end in a resource id,
        // 16-byte ICO entries end in a file offset instead.
        let count = min(Int(group.u16(4)), (group.count - 6) / 14)
        var images: [(entry: Data, image: Data)] = []
        for i in 0..<count {
            let g = 6 + i * 14
            guard let icon = icons.first(where: { $0.id == UInt32(group.u16(g + 12)) }).flatMap(leaf) else { continue }
            images.append((group.subdata(in: g..<g + 12), icon))
        }
        guard !images.isEmpty else { return nil }
        var ico = Data([0, 0, 1, 0])
        ico.append(le: UInt16(images.count))
        var dataOffset = 6 + 16 * images.count
        for (entry, image) in images {
            ico.append(entry.prefix(8))
            ico.append(le: UInt32(image.count))
            ico.append(le: UInt32(dataOffset))
            dataOffset += image.count
        }
        for (_, image) in images { ico.append(image) }
        return ico
    }
}

extension Data {
    func u16(_ i: Int) -> UInt16 { i + 2 <= count ? UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8 : 0 }
    func u32(_ i: Int) -> UInt32 { i + 4 <= count ? UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 : 0 }
    mutating func append<T: FixedWidthInteger>(le v: T) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}
