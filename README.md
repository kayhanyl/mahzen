# Mahzen

A small Wine launcher for running Windows games on Apple Silicon Macs.
Mahzen ("cellar" in Turkish) is a SwiftUI app plus scripts that build its own Wine engine.

It is a personal learning project. It runs Steam and plays Kenshi and Half-Life on an
M4 Pro with macOS 27, and that is about as far as it has been tested.

The app is in English and Turkish and follows the system language. To pick one for Mahzen
only, use System Settings → General → Language & Region → Applications.

## What it does

- **Bottles**: separate Wine prefixes, each with its own Windows version, graphics
  backend, Retina mode, Metal HUD, MSync and verbose logging settings.
- **Three graphics backends**, each a separate engine build:
  - **DXMT**: DirectX 10/11 → Metal (open source). Default; recommended for DX11 games.
  - **D3DMetal**: Apple's DirectX 11/12 → Metal from the Game Porting Toolkit. Some
    DX11 games crash on it (e.g. Kenshi).
  - **WineD3D**: DirectX → OpenGL. Slowest but most compatible; for older games.
- **Steam integration**: installs and launches Steam, lists installed games, and applies
  the overrides Steam's Chromium UI needs (native DXVK for `steamwebhelper`, etc.).
- Pinned programs, opening `.exe` files directly, winecfg/regedit/taskmgr/explorer,
  per-bottle logs.

## Requirements

- Apple Silicon Mac with Rosetta 2 (Wine is built for x86_64)
- macOS 15 or later
- Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Homebrew (the scripts install `bison`, `mingw-w64`, `meson` and `glslang`)
- The Wine source tarball `crossover-sources-26.3.0.tar.gz`
  ([download](https://www.codeweavers.com/crossover/source)); the patches target this tree
- About 5 GB free disk space for the build

## Building the engine

```sh
cd engine
WINE_SRC=/path/to/crossover-sources-26.3.0.tar.gz ./fetch.sh
./deps.sh          # x86_64 sysroot for Wine to link against
./build-wine.sh    # applies patches/, configures and builds Wine (long)
./build-dxvk.sh    # DXVK for Steam's web helper
./package.sh       # installs the engines
```

`fetch.sh` uses `~/Downloads/crossover-sources-26.3.0.tar.gz` if `WINE_SRC` is not set.

`package.sh` installs three engines into `~/Library/Application Support/Mahzen/Engines`:
`cx26.3-dxmt`, `cx26.3-d3dmetal` and `cx26.3-wined3d`. The variants are APFS clones of
one base, so together they take little more space than one.

Notes on the build choices:

- Homebrew no longer ships x86_64 bottles, so the x86_64 runtime dylibs come from
  [Gcenx's Game Porting Toolkit](https://github.com/Gcenx/game-porting-toolkit) bundle and
  the headers come from the source tarball.
- Wine's Windows side is built with mingw-w64 **gcc**, not llvm-mingw: an llvm-built
  `kernelbase.dll` stalls Steam's login.
- 32-bit code is built with `-march=pentium4 -mfpmath=sse`. gcc's x87 default is very
  slow under Rosetta and caused audio crackling in 32-bit games.

## Building the app

```sh
cd app
xcodegen generate
open Mahzen.xcodeproj
```

Bottles live in `~/Library/Application Support/Mahzen/Bottles`.

## Known issues

- Kenshi crashes on D3DMetal right after D3D11 RenderSystem initialisation; use DXMT.
- Only tested on one machine (M4 Pro, macOS 27).

## Credits

- [dappermint/winecx-gptk](https://github.com/dappermint/winecx-gptk) for the Wine patches
  in `engine/patches/` (0001–0022), including the winemac cross-process Metal layer fix
  that makes Steam's UI visible.
- [Gcenx](https://github.com/Gcenx) for the Game Porting Toolkit builds and DXVK-macOS.
- [3Shain/dxmt](https://github.com/3Shain/dxmt), [DXVK](https://github.com/doitsujin/dxvk),
  [MoltenVK](https://github.com/KhronosGroup/MoltenVK).
- [Whisky](https://github.com/Whisky-App/Whisky) as a reference for how a Wine wrapper
  app is put together.

## License

The app and the build scripts are under the [MIT License](LICENSE). The patches in
`engine/patches/` modify Wine and are under the LGPL 2.1 or later, like Wine.

Apple's D3DMetal (Game Porting Toolkit) is proprietary. This repository does not contain
it: `fetch.sh` downloads it, and `package.sh` copies it only into your local engine.
