#!/bin/zsh
# Compiles Wine for x86_64 (runs on Apple Silicon through Rosetta 2).
#   ./build-wine.sh            configure (if needed) + make + install
#   ./build-wine.sh configure  configure only
#
# Wine's Unix side is x86_64 macOS code; its Windows side (the DLLs games load) is PE
# code built by mingw-w64 gcc for both x86_64 and i386, so 32-bit programs run via WoW64.
# gcc rather than llvm-mingw: an llvm-built kernelbase.dll stalls Steam's login
# (found by dappermint/winecx-gptk through module bisection).
#
# patches/ comes from dappermint/winecx-gptk (tag lane/wine11.0-cx26), written for this
# exact source tree. 0003 is what makes Steam's Chromium UI visible: its GPU
# process draws into another process's child windows, which stock winemac leaves black.
set -euo pipefail

# Re-exec under Rosetta so clang targets x86_64 and configure's test programs can run.
if [[ $(arch) != i386 ]]; then exec arch -x86_64 /bin/zsh $0 "$@"; fi

B=${0:A:h}/build
D=$B/deps
OBJ=$B/wine-obj
OUT=$B/install

export PATH=/opt/homebrew/opt/bison/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export PKG_CONFIG_LIBDIR=$D/lib/pkgconfig   # never pick up arm64 Homebrew packages
export MACOSX_DEPLOYMENT_TARGET=14.0
export CC="/usr/bin/clang -arch x86_64" CXX="/usr/bin/clang++ -arch x86_64"
export CFLAGS="-O2 -Wno-deprecated-declarations -Wno-format -Wno-incompatible-function-pointer-types -Wno-int-conversion"
export CROSSCFLAGS="-O2"
# gcc's i686 default is pentiumpro + x87 floating point, which Rosetta emulates very
# slowly: 32-bit dsound's resampler couldn't keep up and Half-Life's audio crackled.
# Every x86 Mac (and Rosetta) has SSE2, and MSVC builds Windows itself with it.
export i386_CFLAGS="-O2 -march=pentium4 -mfpmath=sse"
export CPPFLAGS="-I$D/include"
export LDFLAGS="-L$D/lib -Wl,-headerpad_max_install_names -Wl,-rpath,@loader_path/../../"

SRC=$B/src/sources/wine
# One stamp per patch, so a patch added later still lands on an already-patched tree.
mkdir -p $SRC/.mahzen-patches
for p in ${0:A:h}/patches/*.patch; do
  [[ -f $SRC/.mahzen-patches/${p:t} ]] && continue
  patch -d $SRC -p1 --forward -s < $p
  touch $SRC/.mahzen-patches/${p:t}
done

mkdir -p $OBJ && cd $OBJ

if [[ ! -f Makefile || ${1:-} == configure ]]; then
  $SRC/configure \
    --prefix=$OUT \
    --disable-tests \
    --enable-archs=i386,x86_64 \
    --with-mingw \
    --with-coreaudio --with-cups --with-opencl --with-pthread --with-unwind \
    --with-freetype --with-gnutls --with-sdl --with-vulkan \
    --without-alsa --without-capi --without-dbus --without-ffmpeg --without-fontconfig \
    --without-gettext --without-gettextpo --without-gphoto --without-gssapi \
    --without-gstreamer --without-inotify --without-krb5 --without-netapi --without-oss \
    --without-pcap --without-pcsclite --without-pulse --without-sane --without-udev \
    --without-usb --without-v4l2 --without-wayland --without-x
  [[ ${1:-} == configure ]] && exit 0
fi

# Build-time tools (sfnt2fon) and unix libs use rpath @loader_path/../../, which from
# tools/<x>/ and dlls/<x>/ resolves to the object dir itself.
ln -sf $D/lib/*.dylib $OBJ/
make -j$(sysctl -n hw.ncpu)
rm -rf $OUT
make install-lib >/dev/null
echo "wine ok: $OUT"
