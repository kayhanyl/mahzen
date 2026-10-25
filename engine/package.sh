#!/bin/zsh
# Turns the Wine install into self-contained engines, one per graphics backend:
#
#   <Engines>/cx26.3-wined3d   plain Wine (DirectX -> OpenGL)
#   <Engines>/cx26.3-d3dmetal  + Apple D3DMetal (DirectX 11/12 -> Metal)
#   <Engines>/cx26.3-dxmt      + DXMT (DirectX 10/11 -> Metal)
#
# Wine always loads builtin DLLs from its own lib/wine first, so a backend can't be
# swapped per launch with WINEDLLPATH. Each variant is an APFS clone of the base plus an
# overlay; clones share blocks on disk, so the extra variants cost almost nothing.
set -euo pipefail

B=${0:A:h}/build
ENGINES=${ENGINES:-$HOME/Library/Application Support/Mahzen/Engines}
NAME=cx26.3
GPTK="$B/src/gptk/Game Porting Toolkit.app/Contents/Resources/wine"
DXMT_TAR=$B/dl/dxmt.tar.gz

[[ -f $DXMT_TAR ]] || curl -fL -o $DXMT_TAR https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz

mkdir -p "$ENGINES"
base="$ENGINES/$NAME-wined3d"
rm -rf "$ENGINES/$NAME"-*(N)

# --- base ------------------------------------------------------------------------------
cp -R $B/install "$base"
cp -a $B/deps/lib/*.dylib "$base/lib/"
rm -rf "$base/share/man" "$base/include" "$base/lib/pkgconfig"
# gcc leaves DWARF in every PE file (ntdll.dll 3 MB instead of 0.7 MB); nothing needs it.
for f in "$base"/lib/wine/x86_64-windows/*.{dll,exe,drv,sys}(N); do x86_64-w64-mingw32-strip -s "$f"; done
for f in "$base"/lib/wine/i386-windows/*.{dll,exe,drv,sys}(N); do i686-w64-mingw32-strip -s "$f"; done

# Wine Mono (.NET) and Gecko (HTML), extracted where appwiz.cpl looks ($WINEDATADIR), so
# new prefixes use them in place instead of popping an installer dialog.
mkdir -p "$base/share/wine/mono" "$base/share/wine/gecko"
tar -xf $B/dl/wine-mono.tar.xz -C "$base/share/wine/mono"
tar -xf $B/dl/wine-gecko-x86.tar.xz -C "$base/share/wine/gecko"
tar -xf $B/dl/wine-gecko-x86_64.tar.xz -C "$base/share/wine/gecko"

# DXVK as native DLLs the app copies into a prefix for Chromium-based launchers
# (Steam's web helper), which can't present through D3DMetal or DXMT.
mkdir -p "$base/lib/dxvk"
cp -R $B/dxvk/x64 $B/dxvk/x32 "$base/lib/dxvk/"
rm -f "$base"/lib/dxvk/*/*.a

# --- D3DMetal --------------------------------------------------------------------------
v="$ENGINES/$NAME-d3dmetal"
cp -cR "$base" "$v"
mkdir -p "$v/lib/external"
cp -R "$GPTK/lib/external/"* "$v/lib/external/"
# Only these 64-bit DLLs (PE half + unix half) are D3DMetal; the rest of GPTK's
# lib/wine is its own older Wine and must not leak into ours.
for n in d3d10 d3d11 d3d12 dxgi atidxx64 nvapi64 nvngx nvngx-on-metalfx; do
  cp "$GPTK/lib/wine/x86_64-unix/$n.so" "$v/lib/wine/x86_64-unix/"
  cp "$GPTK/lib/wine/x86_64-windows/$n.dll" "$v/lib/wine/x86_64-windows/"
done
# libd3dshared and D3DMetal are dlopen'ed through @rpath = @loader_path of the unix libs.
ln -sf ../../external/libd3dshared.dylib "$v/lib/wine/x86_64-unix/libd3dshared.dylib"
ln -sf ../../external/D3DMetal.framework "$v/lib/wine/x86_64-unix/D3DMetal.framework"

# --- DXMT ------------------------------------------------------------------------------
v="$ENGINES/$NAME-dxmt"
cp -cR "$base" "$v"
tmp=$(mktemp -d)
tar -xzf $DXMT_TAR -C $tmp
src=$(dirname $(find $tmp -type d -name x86_64-windows | head -1))
for arch in x86_64-windows x86_64-unix i386-windows; do
  [[ -d $src/$arch ]] && cp $src/$arch/* "$v/lib/wine/$arch/"
done
rm -rf $tmp

# --- metadata the app reads ------------------------------------------------------------
wine_version=$("$base/bin/wine" --version 2>/dev/null || echo "wine-11.0")
for backend in wined3d d3dmetal dxmt; do
  cat > "$ENGINES/$NAME-$backend/engine.json" <<EOF
{ "id": "$NAME-$backend", "name": "Mahzen Wine", "wineVersion": "$wine_version", "backend": "$backend" }
EOF
done

xattr -dr com.apple.quarantine "$ENGINES" 2>/dev/null || true
du -sh "$base"
ls "$ENGINES"
