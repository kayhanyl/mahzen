#!/bin/zsh
# Builds DXVK 1.10.3 from the source tarball (dxgi + d3d11 -> Vulkan -> MoltenVK) for 64- and 32-bit.
# Chromium-based launchers (Steam's steamwebhelper) can't present through D3DMetal or
# DXMT, so package.sh gives them these DLLs as native overrides.
set -euo pipefail

B=${0:A:h}/build
SRC=$B/src/sources/dxvk
OUT=$B/dxvk
export PATH=$B/tools/llvm-mingw/bin:/opt/homebrew/bin:/usr/bin:/bin

# DXVK 1.10.3 predates libc++ dropping transitive includes.
grep -q '<algorithm>' $SRC/src/util/config/config.cpp ||
  sed -i '' '1i\
#include <algorithm>
' $SRC/src/util/config/config.cpp
# ...and current mingw-w64 headers now define this stub themselves.
perl -0pi -e 's/typedef struct _D3DDEVINFO_RESOURCEMANAGER\n\{\n  char dummy;\n\} D3DDEVINFO_RESOURCEMANAGER, \* LPD3DDEVINFO_RESOURCEMANAGER;\n//' \
  $SRC/src/d3d9/d3d9_include.h

# Metal has no geometry shaders, cull distances or logic ops, so MoltenVK doesn't expose
# them and stock DXVK refuses every feature level. Make them optional, as Gcenx's
# DXVK-macOS does; apps that need them fail at draw time instead of at device creation.
for f in geometryShader shaderCullDistance logicOp; do
  sed -E -i '' "s/(enabled\.core\.features\.$f +)= VK_TRUE;/\1= supported.core.features.$f;/" \
    $SRC/src/d3d11/d3d11_device.cpp
done

rm -rf $OUT
for bits in 64 32; do
  obj=$B/dxvk-obj$bits
  rm -rf $obj
  meson setup $obj $SRC --cross-file $SRC/build-win$bits.txt --buildtype release \
    --prefix $OUT --bindir x$bits --libdir x$bits -Denable_tests=false -Denable_d3d9=false -Denable_d3d10=false >/dev/null
  ninja -C $obj install | grep -E "error|FAILED" || true
done
ls $OUT/x64 $OUT/x32
