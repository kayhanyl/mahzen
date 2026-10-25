#!/bin/zsh
# Downloads everything the engine build needs into engine/build/.
#   WINE_SRC  path to the Wine source tarball (see README)
set -euo pipefail

ROOT=${0:A:h}
B=$ROOT/build
WINE_SRC=${WINE_SRC:-$HOME/Downloads/crossover-sources-26.3.0.tar.gz}

LLVM_MINGW=20261020
MOLTENVK=v1.4.2
SDL2=2.32.10
GPTK=3.0-3
# Must match MONO_VERSION / GECKO_VERSION in wine/dlls/appwiz.cpl/addons.c.
MONO=10.4.1
GECKO=2.47.4

mkdir -p $B/{src,tools,dl}

fetch() { # url dest
  [[ -f $2 ]] && return
  curl -fL --retry 3 -o $2.part $1
  mv -f $2.part $2
}

fetch https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW/llvm-mingw-$LLVM_MINGW-ucrt-macos-universal.tar.xz $B/dl/llvm-mingw.tar.xz
fetch https://github.com/KhronosGroup/MoltenVK/releases/download/$MOLTENVK/MoltenVK-macos.tar $B/dl/moltenvk.tar
fetch https://github.com/libsdl-org/SDL/releases/download/release-$SDL2/SDL2-$SDL2.tar.gz $B/dl/sdl2.tar.gz
# Only used for its prebuilt x86_64 dylibs and Apple's D3DMetal; its Wine is not used.
fetch https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-$GPTK/game-porting-toolkit-$GPTK.tar.xz $B/dl/gptk.tar.xz

fetch https://dl.winehq.org/wine/wine-mono/$MONO/wine-mono-$MONO-x86.tar.xz $B/dl/wine-mono.tar.xz
fetch https://dl.winehq.org/wine/wine-gecko/$GECKO/wine-gecko-$GECKO-x86.tar.xz $B/dl/wine-gecko-x86.tar.xz
fetch https://dl.winehq.org/wine/wine-gecko/$GECKO/wine-gecko-$GECKO-x86_64.tar.xz $B/dl/wine-gecko-x86_64.tar.xz

[[ -d $B/tools/llvm-mingw ]] || { tar -xf $B/dl/llvm-mingw.tar.xz -C $B/tools && mv $B/tools/llvm-mingw-* $B/tools/llvm-mingw; }
[[ -d $B/tools/MoltenVK ]]   || tar -xf $B/dl/moltenvk.tar -C $B/tools
[[ -d $B/src/sdl2 ]]         || { tar -xzf $B/dl/sdl2.tar.gz -C $B/src && mv $B/src/SDL2-$SDL2 $B/src/sdl2; }
[[ -d $B/src/gptk ]]         || { mkdir -p $B/src/gptk && tar -xf $B/dl/gptk.tar.xz -C $B/src/gptk; }
[[ -d $B/src/sources ]]      || tar -xzf $WINE_SRC -C $B/src

xattr -dr com.apple.quarantine $B/tools $B/src/gptk 2>/dev/null || true
# Build tools run natively (arm64); only the libraries Wine links have to be x86_64.
brew list bison mingw-w64 meson glslang >/dev/null 2>&1 || brew install bison mingw-w64 meson glslang

echo "fetch ok"
