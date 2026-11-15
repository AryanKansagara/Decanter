# Decanter

**Run Windows games and apps on your Mac.** A free, open-source alternative to CrossOver: a native SwiftUI app that manages Windows environments ("bottles") on top of Wine and Apple's D3DMetal, plus the DXMT and DXVK graphics layers.

## Features

- **Three ways to draw DirectX on Metal**, switchable per bottle:
  - **D3DMetal** (Apple Game Porting Toolkit 3.0) for DirectX 11/12, with optional DLSS → MetalFX upscaling
  - **DXMT** for DirectX 10/11, with optional NVIDIA extensions
  - **DXVK** (via MoltenVK) for DirectX 10/11, or **WineD3D** for DirectX 9 and older plus OpenGL
- **One-click game stores:** Steam, Epic Games, GOG Galaxy, Battle.net, EA app, Ubisoft Connect
- **One-click Windows runtimes:** Visual C++, .NET, DirectX 9, PhysX, XACT and core fonts, via Winetricks
- **Game library:** finds installed programs automatically; pin any `.exe`
- **Mac shortcuts:** "Add to Applications" puts a game in Launchpad, Spotlight and the Dock
- **Open With:** double-click any `.exe`/`.msi` in Finder and pick a bottle
- **Per-bottle settings:** Windows version, Retina mode, AVX advertising, ESync, DLL overrides and environment variables
- Built-in tools: Wine configuration, registry editor, task manager, command prompt, uninstaller, logs and "stop all"

## Install

1. Download `Decanter.dmg` from [Releases](https://github.com/AryanKansagara/Decanter/releases) and drag Decanter to Applications.
2. The app isn't notarized, so the first time, right-click Decanter → **Open** → **Open**. Alternatively, run `xattr -dr com.apple.quarantine /Applications/Decanter.app`.
3. Follow the welcome screen: it installs Rosetta 2 if needed and downloads the engines (~470 MB in total).

**Requirements:** macOS 14 or later. Apple Silicon is strongly recommended, and D3DMetal requires it. 16 GB of RAM or more is recommended.

## Usage

1. **New Bottle** (⌘N). Choose **Game Porting Toolkit** for modern DX11/DX12 games, or **Wine Staging** for DX9–11 games and apps.
2. Open **Install** → pick a store, such as Steam, and sign in.
3. Install your game from the store, then double-click it in the library.
4. If a game misbehaves, try a different renderer in **Bottle Settings**, install the runtimes it needs from **Install**, and check **Tools → Show Log**.

## What won't work

Decanter can't run games whose anti-cheat requires real Windows, such as Easy Anti-Cheat, BattlEye, Vanguard or Ricochet when they're enforced. That includes Rocket League, Fortnite, Valorant and Call of Duty online. Use cloud gaming (GeForce NOW, Xbox Cloud) for those. Single-player and co-op games without kernel anti-cheat are the sweet spot.

## How it works

| Piece | Source | License |
|---|---|---|
| Wine Staging 11.21 for macOS | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds) | LGPL |
| Game Porting Toolkit 3.0 (Wine 7.7 + D3DMetal) | [Gcenx/game-porting-toolkit](https://github.com/Gcenx/game-porting-toolkit) | LGPL + [Apple license](https://github.com/user-attachments/files/23971305/License.pdf) |
| DXMT v0.80 | [3Shain/dxmt](https://github.com/3Shain/dxmt) | MIT |
| DXVK-macOS 1.10.3 | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) | zlib |
| Winetricks | [Winetricks/winetricks](https://github.com/Winetricks/winetricks) | LGPL |

None of these are included in the app. They're downloaded on first run from the projects' own releases. D3DMetal is only downloaded after you accept Apple's license.

- **Bottles** are ordinary Wine prefixes in `~/Library/Application Support/Decanter/Bottles`, each with a `decanter.json` holding its settings.
- **DXMT and DXVK** are built as Wine *builtin* DLLs, which Wine only loads from its own `lib/wine` folder. Decanter therefore layers each one onto an APFS clone of the Wine engine, which costs almost no disk space.
- **Launch settings** match what CrossOver uses: `ROSETTA_ADVERTISE_AVX`, `WINEESYNC`, `D3DM_ENABLE_METALFX`, `DXMT_ENABLE_NVEXT`, `DOTNET_EnableWriteXorExecute=0`.

Component versions are pinned in [`Components.swift`](Sources/DecanterKit/Components.swift). Bump them there to update.

## Build from source

Only the Xcode Command Line Tools are needed:

```sh
make test         # unit tests
make integration  # real downloads + real Wine, ~450 MB
make run          # builds build/Decanter.app and opens it
make dmg          # builds build/Decanter.dmg
```

Tag `vX.Y.Z` to have GitHub Actions publish a universal DMG.

## License

MIT for Decanter's own code. The downloaded components keep their own licenses (table above). Not affiliated with CodeWeavers, Apple or the Wine project.
