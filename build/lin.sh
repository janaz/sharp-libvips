#!/usr/bin/env bash
set -e

# Environment / working directories
case ${PLATFORM} in
  linux*)
    LINUX=true
    DEPS=/deps
    TARGET=/target
    PACKAGE=/packaging
    ROOT=/root
    VIPS_CPP_DEP=libvips-cpp.so.42
    ;;
  darwin*)
    DARWIN=true
    DEPS=$PWD/deps
    TARGET=$PWD/target
    PACKAGE=$PWD
    ROOT=$PWD/darwin-x64
    VIPS_CPP_DEP=libvips-cpp.42.dylib
    ;;
esac

mkdir ${DEPS}
mkdir ${TARGET}

# Common build paths and flags
export PKG_CONFIG_LIBDIR="${TARGET}/lib/pkgconfig"
export PATH="${PATH}:${TARGET}/bin"
export CPATH="${TARGET}/include"
export LIBRARY_PATH="${TARGET}/lib"
export LD_LIBRARY_PATH="${TARGET}/lib"
export CFLAGS="${FLAGS}"
export CXXFLAGS="${FLAGS}"
export LDFLAGS="-L${TARGET}/lib"

# On Linux, we need to create a relocatable library
# Note: this is handled for macOS using the `install_name_tool` (see below)
if [ "$LINUX" = true ]; then
  export LDFLAGS+=" -Wl,-rpath='\$\$ORIGIN/'"
fi

# On macOS, we need to explicitly link against the system libraries
if [ "$DARWIN" = true ]; then
  export LDFLAGS+=" -framework CoreServices -framework CoreFoundation -framework Foundation -framework AppKit"
fi

# Run as many parallel jobs as there are available CPU cores
if [ "$LINUX" = true ]; then
  export MAKEFLAGS="-j$(nproc)"
elif [ "$DARWIN" = true ]; then
  export MAKEFLAGS="-j$(sysctl -n hw.logicalcpu)"
fi

# Optimise Rust code for binary size
export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
export CARGO_PROFILE_RELEASE_INCREMENTAL=false
export CARGO_PROFILE_RELEASE_LTO=true
export CARGO_PROFILE_RELEASE_OPT_LEVEL=s
export CARGO_PROFILE_RELEASE_PANIC=abort

# We don't want to use any native libraries, so unset PKG_CONFIG_PATH
unset PKG_CONFIG_PATH

# Common options for curl
CURL="curl --silent --location --retry 3 --retry-max-time 30"

# Dependency version numbers
VERSION_ZLIB=1.2.11
VERSION_FFI=3.3
VERSION_GLIB=2.67.0
VERSION_XML2=2.9.10
VERSION_GSF=1.14.47
VERSION_EXIF=0.6.22
VERSION_LCMS2=2.11
VERSION_JPEG=2.0.6
VERSION_PNG16=1.6.37
VERSION_SPNG=0.6.1
VERSION_WEBP=1.1.0
VERSION_TIFF=4.1.0
VERSION_ORC=0.4.32
VERSION_GETTEXT=0.21
VERSION_EXPAT=2.2.10
VERSION_GIF=5.1.4
VERSION_AOM=0b3b4e96d6f7c75275aa62280ea6c022e8d2f81a
VERSION_HEIF=1.9.1

# Remove patch version component
without_patch() {
  echo "${1%.[[:digit:]]*}"
}

# Check for newer versions
ALL_AT_VERSION_LATEST=true
version_latest() {
  VERSION_LATEST=$($CURL https://release-monitoring.org/api/project/$3 | jq -r '.versions[]' | grep -E -m1 '^[0-9]+(.[0-9]+)*$')
  if [ "$VERSION_LATEST" != "$2" ]; then
    ALL_AT_VERSION_LATEST=false
    echo "$1 version $2 has been superseded by $VERSION_LATEST"
  fi
}
version_latest "zlib" "$VERSION_ZLIB" "5303"
version_latest "ffi" "$VERSION_FFI" "1611"
version_latest "glib" "$VERSION_GLIB" "10024"
version_latest "xml2" "$VERSION_XML2" "1783"
version_latest "gsf" "$VERSION_GSF" "1980"
version_latest "exif" "$VERSION_EXIF" "1607"
version_latest "lcms2" "$VERSION_LCMS2" "9815"
version_latest "jpeg" "$VERSION_JPEG" "1648"
version_latest "png" "$VERSION_PNG16" "1705"
version_latest "spng" "$VERSION_SPNG" "24289"
version_latest "webp" "$VERSION_WEBP" "1761"
version_latest "tiff" "$VERSION_TIFF" "13521"
version_latest "orc" "$VERSION_ORC" "2573"
version_latest "gettext" "$VERSION_GETTEXT" "898"
version_latest "expat" "$VERSION_EXPAT" "770"
#version_latest "gif" "$VERSION_GIF" "1158" # v5.1.5+ provides a Makefile only so will require custom cross-compilation setup
#version_latest "aom" "$VERSION_AOM" "17628" # latest version in release monitoring does not exist
version_latest "heif" "$VERSION_HEIF" "64439"
if [ "$ALL_AT_VERSION_LATEST" = "false" ]; then exit 1; fi

# Download and build dependencies from source

if [ "${PLATFORM%-*}" == "linuxmusl" ] || [ "$DARWIN" = true ]; then
  mkdir ${DEPS}/gettext
  $CURL https://ftp.gnu.org/pub/gnu/gettext/gettext-${VERSION_GETTEXT}.tar.xz | tar xJC ${DEPS}/gettext --strip-components=1
  cd ${DEPS}/gettext/gettext-runtime
  ./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
    --disable-libasprintf --disable-java --disable-native-java --disable-csharp
  make install-strip
fi

mkdir ${DEPS}/zlib
$CURL https://zlib.net/zlib-${VERSION_ZLIB}.tar.xz | tar xJC ${DEPS}/zlib --strip-components=1
cd ${DEPS}/zlib
./configure --prefix=${TARGET} ${LINUX:+--uname=linux} ${DARWIN:+--uname=darwin} --static
make install

mkdir ${DEPS}/ffi
$CURL https://github.com/libffi/libffi/releases/download/v${VERSION_FFI}/libffi-${VERSION_FFI}.tar.gz | tar xzC ${DEPS}/ffi --strip-components=1
cd ${DEPS}/ffi
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --disable-builddir --disable-multi-os-directory --disable-raw-api --disable-structs
make install-strip

mkdir ${DEPS}/glib
$CURL https://download.gnome.org/sources/glib/$(without_patch $VERSION_GLIB)/glib-${VERSION_GLIB}.tar.xz | tar xJC ${DEPS}/glib --strip-components=1
cd ${DEPS}/glib
# Disable tests
sed -i'.bak' "/build_tests =/ s/= .*/= false/" meson.build
if [ "${PLATFORM%-*}" == "linuxmusl" ]; then
  #$CURL https://git.alpinelinux.org/aports/plain/main/glib/musl-libintl.patch | patch -p1 # not compatible with glib 2.65.0
  $CURL https://gist.github.com/kleisauke/f4bda6fc3030cf7b8a4fdb88e2ce8e13/raw/246ac97dfba72ad7607c69eed1810b2354cd2e86/musl-libintl.patch | patch -p1
fi
LDFLAGS=${LDFLAGS/\$/} meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Dinternal_pcre=true -Dinstalled_tests=false -Dlibmount=disabled -Dlibelf=disabled ${DARWIN:+-Dbsymbolic_functions=false}
ninja -C _build
ninja -C _build install

mkdir ${DEPS}/xml2
$CURL http://xmlsoft.org/sources/libxml2-${VERSION_XML2}.tar.gz | tar xzC ${DEPS}/xml2 --strip-components=1
cd ${DEPS}/xml2
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --without-python --without-debug --without-docbook --without-ftp --without-html --without-legacy \
  --without-push --without-schematron --without-lzma --with-zlib=${TARGET}
make install-strip

mkdir ${DEPS}/gsf
$CURL https://download.gnome.org/sources/libgsf/$(without_patch $VERSION_GSF)/libgsf-${VERSION_GSF}.tar.xz | tar xJC ${DEPS}/gsf --strip-components=1
cd ${DEPS}/gsf
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --without-bz2 --without-gdk-pixbuf --with-zlib=${TARGET}
make install-strip

mkdir ${DEPS}/exif
$CURL https://github.com/libexif/libexif/releases/download/libexif-${VERSION_EXIF//./_}-release/libexif-${VERSION_EXIF}.tar.xz | tar xJC ${DEPS}/exif --strip-components=1
cd ${DEPS}/exif
autoreconf -fiv
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking
make install-strip

mkdir ${DEPS}/lcms2
$CURL https://downloads.sourceforge.net/project/lcms/lcms/${VERSION_LCMS2}/lcms2-${VERSION_LCMS2}.tar.gz | tar xzC ${DEPS}/lcms2 --strip-components=1
cd ${DEPS}/lcms2
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking
make install-strip

mkdir ${DEPS}/aom
$CURL https://aomedia.googlesource.com/aom/+archive/${VERSION_AOM}.tar.gz | tar xzC ${DEPS}/aom
cd ${DEPS}/aom
mkdir aom_build
cd aom_build
AOM_AS_FLAGS="${FLAGS}" LDFLAGS=${LDFLAGS/\$/} cmake -G"Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE=${ROOT}/Toolchain.cmake -DCMAKE_INSTALL_PREFIX=${TARGET} -DCMAKE_INSTALL_LIBDIR=lib \
  -DENABLE_DOCS=0 -DENABLE_TESTS=0 -DENABLE_TESTDATA=0 -DENABLE_TOOLS=0 -DENABLE_EXAMPLES=0 \
  -DCONFIG_PIC=1 -DENABLE_NASM=1 ${WITHOUT_NEON:+-DENABLE_NEON=0} \
  ..
make install/strip

mkdir ${DEPS}/heif
$CURL https://github.com/strukturag/libheif/releases/download/v${VERSION_HEIF}/libheif-${VERSION_HEIF}.tar.gz | tar xzC ${DEPS}/heif --strip-components=1
cd ${DEPS}/heif
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --disable-gdk-pixbuf --disable-go --disable-examples --disable-libde265 --disable-x265
sed -i'.bak' -e '/^Requires:/a\'$'\n''Requires.private: aom' libheif.pc # https://github.com/strukturag/libheif/pull/354
make install-strip

mkdir ${DEPS}/jpeg
$CURL https://github.com/libjpeg-turbo/libjpeg-turbo/archive/${VERSION_JPEG}.tar.gz | tar xzC ${DEPS}/jpeg --strip-components=1
cd ${DEPS}/jpeg
LDFLAGS=${LDFLAGS/\$/} cmake -G"Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=${ROOT}/Toolchain.cmake -DCMAKE_INSTALL_PREFIX=${TARGET} -DCMAKE_INSTALL_LIBDIR=${TARGET}/lib \
  -DENABLE_STATIC=TRUE -DENABLE_SHARED=FALSE -DWITH_JPEG8=1 -DWITH_TURBOJPEG=FALSE
make install/strip

mkdir ${DEPS}/png16
$CURL https://downloads.sourceforge.net/project/libpng/libpng16/${VERSION_PNG16}/libpng-${VERSION_PNG16}.tar.xz | tar xJC ${DEPS}/png16 --strip-components=1
cd ${DEPS}/png16
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking
make install-strip

mkdir ${DEPS}/spng
$CURL https://github.com/randy408/libspng/archive/v${VERSION_SPNG}.tar.gz | tar xzC ${DEPS}/spng --strip-components=1
cd ${DEPS}/spng
meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Dstatic_zlib=true
ninja -C _build
ninja -C _build install

mkdir ${DEPS}/webp
$CURL https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${VERSION_WEBP}.tar.gz | tar xzC ${DEPS}/webp --strip-components=1
cd ${DEPS}/webp
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --disable-neon --enable-libwebpmux --enable-libwebpdemux
make install-strip

mkdir ${DEPS}/tiff
$CURL https://download.osgeo.org/libtiff/tiff-${VERSION_TIFF}.tar.gz | tar xzC ${DEPS}/tiff --strip-components=1
cd ${DEPS}/tiff
if [ -n "${CHOST}" ]; then autoreconf -fiv; fi
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --disable-mdi --disable-pixarlog --disable-old-jpeg --disable-cxx --disable-lzma --disable-zstd \
  --with-jpeg-include-dir=${TARGET}/include --with-jpeg-lib-dir=${TARGET}/lib
make install-strip

mkdir ${DEPS}/orc
$CURL https://gstreamer.freedesktop.org/data/src/orc/orc-${VERSION_ORC}.tar.xz | tar xJC ${DEPS}/orc --strip-components=1
cd ${DEPS}/orc
LDFLAGS=${LDFLAGS/\$/} meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Dorc-test=disabled -Dbenchmarks=disabled -Dexamples=disabled -Dgtk_doc=disabled -Dtests=disabled -Dtools=disabled
ninja -C _build
ninja -C _build install

mkdir ${DEPS}/expat
$CURL https://github.com/libexpat/libexpat/releases/download/R_${VERSION_EXPAT//./_}/expat-${VERSION_EXPAT}.tar.xz | tar xJC ${DEPS}/expat --strip-components=1
cd ${DEPS}/expat
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared \
  --disable-dependency-tracking --without-xmlwf --without-docbook --without-getrandom --without-sys-getrandom
make install

mkdir ${DEPS}/gif
$CURL https://downloads.sourceforge.net/project/giflib/giflib-${VERSION_GIF}.tar.gz | tar xzC ${DEPS}/gif --strip-components=1
cd ${DEPS}/gif
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking
make install-strip

mkdir ${DEPS}/vips
$CURL https://github.com/libvips/libvips/releases/download/v${VERSION_VIPS}/vips-${VERSION_VIPS}.tar.gz | tar xzC ${DEPS}/vips --strip-components=1
cd ${DEPS}/vips
PKG_CONFIG="pkg-config --static" ./configure --host=${CHOST} --prefix=${TARGET} --enable-shared --disable-static --disable-dependency-tracking \
  --disable-debug --disable-deprecated --disable-introspection --without-analyze --without-cfitsio --without-fftw \
  --without-imagequant --without-magick --without-matio --without-nifti --without-OpenEXR \
  --without-openslide --without-pdfium --without-poppler --without-ppm --without-radiance \
  ${LINUX:+LDFLAGS="$LDFLAGS -Wl,-Bsymbolic-functions"}
# https://docs.fedoraproject.org/en-US/packaging-guidelines/#_removing_rpath
sed -i'.bak' 's|^hardcode_libdir_flag_spec=.*|hardcode_libdir_flag_spec=""|g' libtool
make install-strip

# Cleanup
rm -rf ${TARGET}/lib/{pkgconfig,.libs,*.la,cmake}

mkdir ${TARGET}/lib-filtered
mv ${TARGET}/lib/glib-2.0 ${TARGET}/lib-filtered

# Pack only the relevant libraries
# Note: we can't use ldd on Linux, since that can only be executed on the target machine
# Note 2: we modify all dylib dependencies to use relative paths on macOS
function copydeps {
  local base=$1
  local dest_dir=$2

  cp -L $base $dest_dir/$base
  chmod 644 $dest_dir/$base

  if [ "$LINUX" = true ]; then
    local dependencies=$(readelf -d $base | grep NEEDED | awk '{ print $5 }' | tr -d '[]')
  elif [ "$DARWIN" = true ]; then
    local dependencies=$(otool -LX $base | awk '{print $1}' | grep $TARGET)

    install_name_tool -id @rpath/$base $dest_dir/$base
  fi

  for dep in $dependencies; do
    base_dep=$(basename $dep)

    [ ! -f "$PWD/$base_dep" ] && echo "$base_dep does not exist in $PWD" && continue
    echo "$base depends on $base_dep"

    if [ ! -f "$dest_dir/$base_dep" ]; then
      if [ "$DARWIN" = true ]; then
        install_name_tool -change $dep @rpath/$base_dep $dest_dir/$base
      fi

      # Call this function (recursive) on each dependency of this library
      copydeps $base_dep $dest_dir
    fi
  done;
}

cd ${TARGET}/lib
copydeps ${VIPS_CPP_DEP} ${TARGET}/lib-filtered

# Create JSON file of version numbers
cd ${TARGET}
printf "{\n\
  \"aom\": \"${VERSION_AOM}\",\n\
  \"exif\": \"${VERSION_EXIF}\",\n\
  \"expat\": \"${VERSION_EXPAT}\",\n\
  \"ffi\": \"${VERSION_FFI}\",\n\
  \"gettext\": \"${VERSION_GETTEXT}\",\n\
  \"gif\": \"${VERSION_GIF}\",\n\
  \"glib\": \"${VERSION_GLIB}\",\n\
  \"gsf\": \"${VERSION_GSF}\",\n\
  \"heif\": \"${VERSION_HEIF}\",\n\
  \"jpeg\": \"${VERSION_JPEG}\",\n\
  \"lcms\": \"${VERSION_LCMS2}\",\n\
  \"orc\": \"${VERSION_ORC}\",\n\
  \"png\": \"${VERSION_PNG16}\",\n\
  \"spng\": \"${VERSION_SPNG}\",\n\
  \"tiff\": \"${VERSION_TIFF}\",\n\
  \"vips\": \"${VERSION_VIPS}\",\n\
  \"webp\": \"${VERSION_WEBP}\",\n\
  \"xml\": \"${VERSION_XML2}\",\n\
  \"zlib\": \"${VERSION_ZLIB}\"\n\
}" >versions.json

printf "\"${PLATFORM}\"" >platform.json

# Add third-party notices
$CURL -O https://raw.githubusercontent.com/lovell/sharp-libvips/master/THIRD-PARTY-NOTICES.md

# Create the tarball
rm -rf lib
mv lib-filtered lib
tar chzf ${PACKAGE}/libvips-${VERSION_VIPS}-${PLATFORM}.tar.gz \
  include \
  lib \
  *.json \
  THIRD-PARTY-NOTICES.md

# Recompress using AdvanceCOMP, ~5% smaller
advdef --recompress --shrink-insane ${PACKAGE}/libvips-${VERSION_VIPS}-${PLATFORM}.tar.gz

# Recompress using Brotli, ~15% smaller
gunzip -c ${PACKAGE}/libvips-${VERSION_VIPS}-${PLATFORM}.tar.gz | brotli -o ${PACKAGE}/libvips-${VERSION_VIPS}-${PLATFORM}.tar.br

# Allow tarballs to be read outside container
chmod 644 ${PACKAGE}/libvips-${VERSION_VIPS}-${PLATFORM}.tar.*
