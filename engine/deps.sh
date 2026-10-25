#!/bin/zsh
# Builds an x86_64 sysroot (engine/build/deps) that Wine's configure can link against.
#
# Homebrew no longer ships x86_64 bottles, so the runtime libraries come prebuilt from
# Gcenx's Game Porting Toolkit bundle, headers come from the Wine source tarball, and
# MoltenVK comes from Khronos. Every dylib gets an @rpath install name so the finished
# engine can find them relative to itself.
set -euo pipefail

B=${0:A:h}/build
D=$B/deps
GPTK="$B/src/gptk/Game Porting Toolkit.app/Contents/Resources/wine"
SRC=$B/src/sources

rm -rf $D && mkdir -p $D/{lib,include,lib/pkgconfig}

# --- libraries -------------------------------------------------------------------------
cp -a "$GPTK"/lib/*.dylib $D/lib/
lipo -thin x86_64 $B/tools/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib -output $D/lib/libMoltenVK.dylib

for f in $D/lib/*.dylib(.); do
  install_name_tool -id @rpath/${f:t} $f 2>/dev/null
done
# Bare names like libgnutls.dylib are symlinks/copies; point them at the versioned id.
for pair in freetype:libfreetype.6 gnutls:libgnutls.30 SDL2:libSDL2-2.0.0; do
  name=${pair%%:*} real=${pair#*:}
  rm -f $D/lib/lib$name.dylib && ln -s $real.dylib $D/lib/lib$name.dylib
done
codesign -f -s - $D/lib/*.dylib(.) 2>/dev/null

# --- headers ---------------------------------------------------------------------------
mkdir -p $D/include/freetype2
cp -R $SRC/freetype/include/* $D/include/freetype2/

mkdir -p $D/include/gnutls
cp $SRC/gnutls/gnutls/lib/includes/gnutls/*.h $D/include/gnutls/
# GPTK ships gnutls 3.8.x; the API Wine uses is identical across 3.8 releases.
sed -e "s/@VERSION@/3.8.3/; s/@MAJOR_VERSION@/3/; s/@MINOR_VERSION@/8/; s/@PATCH_VERSION@/3/; s/@NUMBER_VERSION@/0x030803/" \
    -e 's|^@DEFINE_IOVEC_T@$|#include <sys/uio.h>\
typedef struct iovec giovec_t;|' \
    $SRC/gnutls/gnutls/lib/includes/gnutls/gnutls.h.in > $D/include/gnutls/gnutls.h

mkdir -p $D/include/SDL2
cp $B/src/sdl2/include/*.h $D/include/SDL2/

# --- pkg-config ------------------------------------------------------------------------
pc() { # name version cflags libs
  printf 'Name: %s\nDescription: %s\nVersion: %s\nCflags: %s\nLibs: %s\n' $1 $1 $2 "$3" "$4" > $D/lib/pkgconfig/$1.pc
}
pc freetype2 26.1.20 "-I$D/include/freetype2" "-L$D/lib -lfreetype"
pc gnutls    3.8.3   "-I$D/include"           "-L$D/lib -lgnutls"
pc sdl2      2.32.10 "-I$D/include/SDL2 -D_THREAD_SAFE" "-L$D/lib -lSDL2"

echo "deps ok: $(ls $D/lib/*.dylib | wc -l | tr -d ' ') dylibs"
