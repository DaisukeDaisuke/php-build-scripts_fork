#!/bin/bash
[ -z "$PHP_VERSION" ] && PHP_VERSION="8.0.28"

ZLIB_VERSION="1.2.13"
GMP_VERSION="6.2.1"
CURL_VERSION="curl-8_0_1"
YAML_VERSION="0.2.5"
LEVELDB_VERSION="1c7564468b41610da4f498430e795ca4de0931ff"
LIBXML_VERSION="2.10.1" #2.10.2 requires automake 1.16.3, which isn't easily available on Ubuntu 20.04
LIBPNG_VERSION="1.6.39"
LIBJPEG_VERSION="9e"
OPENSSL_VERSION="1.1.1t"
LIBZIP_VERSION="1.9.2"
SQLITE3_YEAR="2023"
SQLITE3_VERSION="3410200" #3.41.2
LIBDEFLATE_VERSION="495fee110ebb48a5eb63b75fd67e42b2955871e2" #1.18

EXT_PTHREADS_VERSION_PM4="4.2.1"
EXT_PTHREADS_VERSION_PM5="5.3.1"
EXT_PTHREADS_VERSION="$EXT_PTHREADS_VERSION_PM4"
EXT_YAML_VERSION="2.2.3"
EXT_LEVELDB_VERSION="317fdcd8415e1566fc2835ce2bdb8e19b890f9f3"
EXT_CHUNKUTILS2_VERSION="0.3.5"
EXT_XDEBUG_VERSION="3.2.1"
EXT_IGBINARY_VERSION="3.2.14"
EXT_CRYPTO_VERSION="0.3.2"
EXT_RECURSIONGUARD_VERSION="0.1.0"
EXT_LIBDEFLATE_VERSION="0.2.1"
EXT_MORTON_VERSION="0.1.2"
EXT_XXHASH_VERSION="0.1.1"

function write_out {
	echo "[$1] $2"
}

function write_error {
	write_out ERROR "$1" >&2
}

function write_status {
	echo -n " $1..."
}

function write_library {
  echo -n "[$1 $2]"
}

function write_caching {
  write_status "using cache"
}

function write_download {
	write_status "downloading"
}
function write_compile {
	write_status "compiling"
}
function write_install {
	write_status "installing"
}
function write_done {
	echo -n " done!"
}
function cant_use_cache {
	if [ -f "$1/.compile.sh.cache" ]; then
		return 1
	else
		return 0
	fi
}
function mark_cache {
	touch "./.compile.sh.cache"
}

echo "[PocketMine] PHP compiler for Linux, MacOS and Android"
DIR="$(pwd)"
BASE_BUILD_DIR="$DIR/install_data"
#libtool and autoconf have a "feature" where it looks for install.sh/install-sh in ./ ../ and ../../
#this extra subdir makes sure that it doesn't find anything it's not supposed to be looking for.
BUILD_DIR="$BASE_BUILD_DIR/subdir"
LIB_BUILD_DIR="$BUILD_DIR/lib"
INSTALL_DIR="$DIR/bin/php7"

date > "$DIR/install.log" 2>&1

uname -a >> "$DIR/install.log" 2>&1
echo "[INFO] Checking dependencies"

COMPILE_SH_DEPENDENCIES=( make autoconf automake m4 getconf gzip bzip2 bison g++ git cmake pkg-config re2c)
ERRORS=0
for(( i=0; i<${#COMPILE_SH_DEPENDENCIES[@]}; i++ ))
do
	type "${COMPILE_SH_DEPENDENCIES[$i]}" >> "$DIR/install.log" 2>&1 || { write_error "Please install \"${COMPILE_SH_DEPENDENCIES[$i]}\""; ((ERRORS++)); }
done

type wget >> "$DIR/install.log" 2>&1 || type curl >> "$DIR/install.log" || { echo >&2 "[ERROR] Please install \"wget\" or \"curl\""; ((ERRORS++)); }

if [ "$(uname -s)" == "Darwin" ]; then
	type glibtool >> "$DIR/install.log" 2>&1 || { echo >&2 "[ERROR] Please install GNU libtool"; ((ERRORS++)); }
	export LIBTOOL=glibtool
	export LIBTOOLIZE=glibtoolize
	export PATH="/opt/homebrew/opt/bison/bin:$PATH"
	[[ $(bison --version) == "bison (GNU Bison) 3."* ]] || { echo >&2 "[ERROR] MacOS bundled bison is too old. Install bison using Homebrew and update your PATH variable according to its instructions before running this script."; ((ERRORS++)); }
else
	type libtool >> "$DIR/install.log" 2>&1 || { echo >&2 "[ERROR] Please install \"libtool\" or \"libtool-bin\""; ((ERRORS++)); }
	export LIBTOOL=libtool
	export LIBTOOLIZE=libtoolize
fi

if [ $ERRORS -ne 0 ]; then
	exit 1
fi

#Needed to use aliases
shopt -s expand_aliases
type wget >> "$DIR/install.log" 2>&1
if [ $? -eq 0 ]; then
	alias _download_file="wget --no-check-certificate -nv -O -"
else
	type curl >> "$DIR/install.log" 2>&1
	if [ $? -eq 0 ]; then
		alias _download_file="curl --insecure --silent --show-error --location --globoff"
	else
		echo "error, curl or wget not found"
		exit 1
	fi
fi

DOWNLOAD_CACHE=""

function download_file {
	local url="$1"
	local prefix="$2"
	local cached_filename="$prefix-${url##*/}"

	if [[ "$DOWNLOAD_CACHE" != "" ]]; then
		if [[ ! -d "$DOWNLOAD_CACHE" ]]; then
			mkdir "$DOWNLOAD_CACHE" >> "$DIR/install.log" 2>&1
		fi
		if [[ -f "$DOWNLOAD_CACHE/$cached_filename" ]]; then
			echo "Cache hit for URL: $url" >> "$DIR/install.log"
		else
			echo "Downloading file to cache: $url" >> "$DIR/install.log"
			_download_file "$1" > "$DOWNLOAD_CACHE/$cached_filename" 2>> "$DIR/install.log"
		fi
		cat "$DOWNLOAD_CACHE/$cached_filename" 2>> "$DIR/install.log"
	else
		echo "Downloading non-cached file: $url" >> "$DIR/install.log"
		_download_file "$1" 2>> "$DIR/install.log"
	fi
}

#if type llvm-gcc >/dev/null 2>&1; then
#	export CC="llvm-gcc"
#	export CXX="llvm-g++"
#	export AR="llvm-ar"
#	export AS="llvm-as"
#	export RANLIB=llvm-ranlib
#else
	export CC="gcc"
	export CXX="g++"
	#export AR="gcc-ar"
	export RANLIB=ranlib
#fi

COMPILE_FOR_ANDROID=no
HAVE_MYSQLI="--enable-mysqlnd --with-mysqli=mysqlnd"
COMPILE_TARGET=""
IS_CROSSCOMPILE="no"
IS_WINDOWS="no"
DO_OPTIMIZE="no"
OPTIMIZE_TARGET=""
DO_STATIC="no"
DO_CLEANUP="yes"
COMPILE_DEBUG="no"
HAVE_VALGRIND="--without-valgrind"
HAVE_OPCACHE="yes"
HAVE_XDEBUG="yes"
FSANITIZE_OPTIONS=""
FLAGS_LTO=""

LD_PRELOAD=""

COMPILE_GD="no"

PM_VERSION_MAJOR="4"

while getopts "::t:j:srdxff:gnva:P:c:l:" OPTION; do

	case $OPTION in
		l)
			mkdir "$OPTARG" 2> /dev/null
			LIB_BUILD_DIR="$(cd $OPTARG; pwd)"
			write_out opt "Reusing previously built libraries in $LIB_BUILD_DIR if found"
			write_out WARNING "Reusing previously built libraries may break if different args were used!"
			;;
		c)
			mkdir "$OPTARG" 2> /dev/null
			DOWNLOAD_CACHE="$(cd $OPTARG; pwd)"
			write_out opt "Caching downloaded files in $DOWNLOAD_CACHE and reusing if available"
			;;
		t)
			echo "[opt] Set target to $OPTARG"
			COMPILE_TARGET="$OPTARG"
			;;
		j)
			echo "[opt] Set make threads to $OPTARG"
			THREADS="$OPTARG"
			;;
		d)
			echo "[opt] Will compile everything with debugging symbols, will not remove sources"
			COMPILE_DEBUG="yes"
			DO_CLEANUP="no"
			CFLAGS="$CFLAGS -g"
			CXXFLAGS="$CXXFLAGS -g"
			;;
		x)
			echo "[opt] Doing cross-compile"
			IS_CROSSCOMPILE="yes"
			;;
		s)
			echo "[opt] Will compile everything statically"
			DO_STATIC="yes"
			CFLAGS="$CFLAGS -static"
			;;
		f)
			echo "[opt] Enabling abusive optimizations..."
			DO_OPTIMIZE="yes"
			OPTIMIZE_TARGET="$OPTARG"
			;;
		g)
			echo "[opt] Will enable GD2"
			COMPILE_GD="yes"
			;;
		n)
			echo "[opt] Will not remove sources after completing compilation"
			DO_CLEANUP="no"
			;;
		v)
			echo "[opt] Will enable valgrind support in PHP"
			HAVE_VALGRIND="--with-valgrind"
			;;
		a)
			echo "[opt] Will pass -fsanitize=$OPTARG to compilers and linkers"
			FSANITIZE_OPTIONS="$OPTARG"
			;;
		P)
			PM_VERSION_MAJOR="$OPTARG"
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
	esac
done

if [ "$PM_VERSION_MAJOR" -ge 5 ]; then
	EXT_PTHREADS_VERSION="$EXT_PTHREADS_VERSION_PM5"
else
	EXT_PTHREADS_VERSION="$EXT_PTHREADS_VERSION_PM4"
fi
write_out "opt" "Compiling with configuration for PocketMine-MP $PM_VERSION_MAJOR"

GMP_ABI=""
TOOLCHAIN_PREFIX=""
OPENSSL_TARGET=""
CMAKE_GLOBAL_EXTRA_FLAGS=""

if [ "$IS_CROSSCOMPILE" == "yes" ]; then
	export CROSS_COMPILER="$PATH"
	if [[ "$COMPILE_TARGET" == "win" ]] || [[ "$COMPILE_TARGET" == "win64" ]]; then
		TOOLCHAIN_PREFIX="x86_64-w64-mingw32"
		[ -z "$march" ] && march=x86_64;
		[ -z "$mtune" ] && mtune=nocona;
		CFLAGS="$CFLAGS -mconsole"
		CONFIGURE_FLAGS="--host=$TOOLCHAIN_PREFIX --target=$TOOLCHAIN_PREFIX --build=$TOOLCHAIN_PREFIX"
		IS_WINDOWS="yes"
		OPENSSL_TARGET="mingw64"
		GMP_ABI="64"
		echo "[INFO] Cross-compiling for Windows 64-bit"
	elif [ "$COMPILE_TARGET" == "mac" ]; then
		[ -z "$march" ] && march=prescott;
		[ -z "$mtune" ] && mtune=generic;
		CFLAGS="$CFLAGS -fomit-frame-pointer";
		TOOLCHAIN_PREFIX="i686-apple-darwin10"
		CONFIGURE_FLAGS="--host=$TOOLCHAIN_PREFIX"
		#zlib doesn't use the correct ranlib
		RANLIB=$TOOLCHAIN_PREFIX-ranlib
		CFLAGS="$CFLAGS -Qunused-arguments -Wno-error=unused-command-line-argument-hard-error-in-future"
		ARCHFLAGS="-Wno-error=unused-command-line-argument-hard-error-in-future"
		OPENSSL_TARGET="darwin64-x86_64-cc"
		GMP_ABI="32"
		echo "[INFO] Cross-compiling for Intel MacOS"
	elif [ "$COMPILE_TARGET" == "android-aarch64" ]; then
		COMPILE_FOR_ANDROID=yes
		[ -z "$march" ] && march="armv8-a";
		[ -z "$mtune" ] && mtune=generic;
		TOOLCHAIN_PREFIX="aarch64-linux-musl"
		CONFIGURE_FLAGS="--host=$TOOLCHAIN_PREFIX"
		CFLAGS="-static $CFLAGS"
		CXXFLAGS="-static $CXXFLAGS"
		LDFLAGS="-static -static-libgcc -Wl,-static"
		DO_STATIC="yes"
		OPENSSL_TARGET="linux-aarch64"
		export ac_cv_func_fnmatch_works=yes #musl should be OK
		echo "[INFO] Cross-compiling for Android ARMv8 (aarch64)"
	#TODO: add cross-compile for aarch64 platforms (ios, rpi)
	else
		echo "Please supply a proper platform [mac win win64 android-aarch64] to cross-compile"
		exit 1
	fi
else
	if [[ "$COMPILE_TARGET" == "" ]] && [[ "$(uname -s)" == "Darwin" ]]; then
		if [ "$(uname -m)" == "arm64" ]; then
			COMPILE_TARGET="mac-arm64"
		else
			COMPILE_TARGET="mac-x86-64"
		fi
	fi
	if [[ "$COMPILE_TARGET" == "linux" ]] || [[ "$COMPILE_TARGET" == "linux64" ]]; then
		[ -z "$march" ] && march=x86-64;
		[ -z "$mtune" ] && mtune=skylake;
		CFLAGS="$CFLAGS -m64"
		GMP_ABI="64"
		OPENSSL_TARGET="linux-x86_64"
		echo "[INFO] Compiling for Linux x86_64"
	elif [[ "$COMPILE_TARGET" == "mac-x86-64" ]]; then
		[ -z "$march" ] && march=core2;
		[ -z "$mtune" ] && mtune=generic;
		[ -z "$MACOSX_DEPLOYMENT_TARGET" ] && export MACOSX_DEPLOYMENT_TARGET=10.9;
		CFLAGS="$CFLAGS -m64 -arch x86_64 -fomit-frame-pointer -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
		LDFLAGS="$LDFLAGS -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
		if [ "$DO_STATIC" == "no" ]; then
			LDFLAGS="$LDFLAGS -Wl,-rpath,@loader_path/../lib";
			export DYLD_LIBRARY_PATH="@loader_path/../lib"
		fi
		CFLAGS="$CFLAGS -Qunused-arguments -Wno-error=unused-command-line-argument-hard-error-in-future"
		ARCHFLAGS="-Wno-error=unused-command-line-argument-hard-error-in-future"
		GMP_ABI="64"
		OPENSSL_TARGET="darwin64-x86_64-cc"
		CMAKE_GLOBAL_EXTRA_FLAGS="-DCMAKE_OSX_ARCHITECTURES=x86_64"
		echo "[INFO] Compiling for MacOS x86_64"
	#TODO: add aarch64 platforms (ios, android, rpi)
	elif [[ "$COMPILE_TARGET" == "mac-arm64" ]]; then
		[ -z "$MACOSX_DEPLOYMENT_TARGET" ] && export MACOSX_DEPLOYMENT_TARGET=11.0;
		CFLAGS="$CFLAGS -arch arm64 -fomit-frame-pointer -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
		LDFLAGS="$LDFLAGS -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
		if [ "$DO_STATIC" == "no" ]; then
			LDFLAGS="$LDFLAGS -Wl,-rpath,@loader_path/../lib";
			export DYLD_LIBRARY_PATH="@loader_path/../lib"
		fi
		CFLAGS="$CFLAGS -Qunused-arguments"
		GMP_ABI="64"
		OPENSSL_TARGET="darwin64-arm64-cc"
		CMAKE_GLOBAL_EXTRA_FLAGS="-DCMAKE_OSX_ARCHITECTURES=arm64"
		echo "[INFO] Compiling for MacOS M1"
	elif [[ "$COMPILE_TARGET" != "" ]]; then
		echo "Please supply a proper platform [mac-arm64 mac-x86-64 linux linux64] to compile for"
		exit 1
	elif [ -z "$CFLAGS" ]; then
		if [ `getconf LONG_BIT` == "64" ]; then
			echo "[INFO] Compiling for current machine using 64-bit"
			if [ "$(uname -m)" != "aarch64" ]; then
				CFLAGS="-m64 $CFLAGS"
			fi
			GMP_ABI="64"
		else
			echo "[ERROR] PocketMine-MP is no longer supported on 32-bit systems"
			exit 1
		fi
	fi
fi

if [ "$DO_STATIC" == "yes" ]; then
	HAVE_OPCACHE="no" #doesn't work on static builds
	echo "[warning] OPcache cannot be used on static builds; this may have a negative effect on performance"
	if [ "$FSANITIZE_OPTIONS" != "" ]; then
		echo "[warning] Sanitizers cannot be used on static builds"
	fi
	if [ "$HAVE_XDEBUG" == "yes" ]; then
	  write_out "warning" "Xdebug cannot be built in static mode"
	  HAVE_XDEBUG="no"
	fi
fi

if [ "$DO_OPTIMIZE" != "no" ]; then
	#FLAGS_LTO="-fvisibility=hidden -flto"
	CFLAGS="$CFLAGS -O2 -ftree-vectorize -fomit-frame-pointer -funswitch-loops -fivopts"
	if [ "$COMPILE_TARGET" != "mac-x86-64" ] && [ "$COMPILE_TARGET" != "mac-arm64" ]; then
		CFLAGS="$CFLAGS -funsafe-loop-optimizations -fpredictive-commoning -ftracer -ftree-loop-im -frename-registers -fcx-limited-range"
	fi

	if [ "$OPTIMIZE_TARGET" == "arm" ]; then
		CFLAGS="$CFLAGS -mfpu=vfp"
	elif [ "$OPTIMIZE_TARGET" == "x86_64" ]; then
		CFLAGS="$CFLAGS -mmmx -msse -msse2 -msse3 -mfpmath=sse -free -msahf -ftree-parallelize-loops=4"
	elif [ "$OPTIMIZE_TARGET" == "x86" ]; then
		CFLAGS="$CFLAGS -mmmx -msse -msse2 -mfpmath=sse -m128bit-long-double -malign-double -ftree-parallelize-loops=4"
	fi
fi

if [ "$TOOLCHAIN_PREFIX" != "" ]; then
		export CC="$TOOLCHAIN_PREFIX-gcc"
		export CXX="$TOOLCHAIN_PREFIX-g++"
		export AR="$TOOLCHAIN_PREFIX-ar"
		export RANLIB="$TOOLCHAIN_PREFIX-ranlib"
		export CPP="$TOOLCHAIN_PREFIX-cpp"
		export LD="$TOOLCHAIN_PREFIX-ld"
fi

echo "#include <stdio.h>" > test.c
echo "int main(void){" >> test.c
echo "printf(\"Hello world\n\");" >> test.c
echo "return 0;" >> test.c
echo "}" >> test.c


type $CC >> "$DIR/install.log" 2>&1 || { echo >&2 "[ERROR] Please install \"$CC\""; exit 1; }

if [ -z "$THREADS" ]; then
	write_out "WARNING" "Only 1 thread is used by default. Increase thread count using -j (e.g. -j 4) to compile faster."	
	THREADS=1;
fi
[ -z "$march" ] && march=native;
[ -z "$mtune" ] && mtune=native;
[ -z "$CFLAGS" ] && CFLAGS="";

if [ "$DO_STATIC" == "no" ]; then
	[ -z "$LDFLAGS" ] && LDFLAGS="-Wl,-rpath='\$\$ORIGIN/../lib' -Wl,-rpath-link='\$\$ORIGIN/../lib'";
fi

[ -z "$CONFIGURE_FLAGS" ] && CONFIGURE_FLAGS="";

if [ "$mtune" != "none" ]; then
	$CC -march=$march -mtune=$mtune $CFLAGS -o test test.c >> "$DIR/install.log" 2>&1
	if [ $? -eq 0 ]; then
		CFLAGS="-march=$march -mtune=$mtune -fno-gcse $CFLAGS"
	fi
else
	$CC -march=$march $CFLAGS -o test test.c >> "$DIR/install.log" 2>&1
	if [ $? -eq 0 ]; then
		CFLAGS="-march=$march -fno-gcse $CFLAGS"
	fi
fi

if [ "$FSANITIZE_OPTIONS" != "" ]; then
	CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" $CC -fsanitize=$FSANITIZE_OPTIONS -o asan-test test.c >> "$DIR/install.log" 2>&1 && \
		chmod +x asan-test >> "$DIR/install.log" 2>&1 && \
		./asan-test >> "$DIR/install.log" 2>&1 && \
		rm asan-test >> "$DIR/install.log" 2>&1
	if [ $? -ne 0 ]; then
		echo "[ERROR] One or more sanitizers are not working. Check install.log for details."
		exit 1
	else
		echo "[INFO] All selected sanitizers are working"
	fi
fi

rm test.* >> "$DIR/install.log" 2>&1
rm test >> "$DIR/install.log" 2>&1

export CC="$CC"
export CXX="$CXX"
export CFLAGS="-O2 -fPIC $CFLAGS"
export CXXFLAGS="$CFLAGS $CXXFLAGS"
export LDFLAGS="$LDFLAGS"
export CPPFLAGS="$CPPFLAGS"
export LIBRARY_PATH="$INSTALL_DIR/lib:$LIBRARY_PATH"
export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig"

#some stuff (like curl) makes assumptions about library paths that break due to different behaviour in pkgconf vs pkg-config
export PKG_CONFIG_ALLOW_SYSTEM_LIBS="yes"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS="yes"

rm -r -f "$BASE_BUILD_DIR" >> "$DIR/install.log" 2>&1
rm -r -f bin/ >> "$DIR/install.log" 2>&1
mkdir -m 0755 "$BASE_BUILD_DIR" >> "$DIR/install.log" 2>&1
mkdir -m 0755 "$BUILD_DIR" >> "$DIR/install.log" 2>&1
mkdir -m 0755 -p $INSTALL_DIR >> "$DIR/install.log" 2>&1
mkdir -m 0755 -p "$LIB_BUILD_DIR" >> "$DIR/install.log" 2>&1
cd "$BUILD_DIR"
set -e

#PHP 7
echo -n "[PHP] downloading $PHP_VERSION..."

download_file "https://github.com/php/php-src/archive/php-$PHP_VERSION.tar.gz" "php" | tar -zx >> "$DIR/install.log" 2>&1
mv php-src-php-$PHP_VERSION php
echo " done!"

function build_zlib {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--static"
	else
		local EXTRA_FLAGS="--shared"
	fi

	write_library zlib "$ZLIB_VERSION"
	local zlib_dir="./zlib-$ZLIB_VERSION"

	if cant_use_cache "$zlib_dir"; then
		rm -rf "$zlib_dir"
		write_download
		download_file "https://github.com/madler/zlib/archive/v$ZLIB_VERSION.tar.gz" "zlib" | tar -zx >> "$DIR/install.log" 2>&1
		echo -n " checking..."
		cd "$zlib_dir"
		RANLIB=$RANLIB ./configure --prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS >> "$DIR/install.log" 2>&1
		echo -n " compiling..."
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$zlib_dir"
	fi
	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	cd ..
	if [ "$DO_STATIC" != "yes" ]; then
		rm -f "$INSTALL_DIR/lib/libz.a"
	fi
	echo " done!"
}

function build_gmp {
	export jm_cv_func_working_malloc=yes
	export ac_cv_func_malloc_0_nonnull=yes
	export jm_cv_func_working_realloc=yes
	export ac_cv_func_realloc_0_nonnull=yes

	if [ "$IS_CROSSCOMPILE" == "yes" ]; then
		local EXTRA_FLAGS=""
	else
		local EXTRA_FLAGS="--disable-assembly"
	fi

	write_library gmp "$GMP_VERSION"
	local gmp_dir="./gmp-$GMP_VERSION"

	if cant_use_cache "$gmp_dir"; then
		rm -rf "$gmp_dir"
		write_download
		download_file "https://gmplib.org/download/gmp/gmp-$GMP_VERSION.tar.bz2" "gmp" | tar -jx >> "$DIR/install.log" 2>&1
		echo -n " checking..."
		cd "$gmp_dir"
		RANLIB=$RANLIB ./configure --prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS \
		--disable-posix-threads \
		--enable-static \
		--disable-shared \
		$CONFIGURE_FLAGS ABI="$GMP_ABI" >> "$DIR/install.log" 2>&1
		echo -n " compiling..."
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$gmp_dir"
	fi
	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	cd ..
	echo " done!"
}

function build_openssl {
	#OpenSSL
	OPENSSL_CMD="./config"
	if [ "$OPENSSL_TARGET" != "" ]; then
		local OPENSSL_CMD="./Configure $OPENSSL_TARGET"
	fi
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="no-shared"
	else
		local EXTRA_FLAGS="shared"
	fi

	WITH_OPENSSL="--with-openssl=$INSTALL_DIR"

	write_library openssl "$OPENSSL_VERSION"
	local openssl_dir="./openssl-$OPENSSL_VERSION"

	if cant_use_cache "$openssl_dir"; then
		rm -rf "$openssl_dir"
		write_download
		download_file "http://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" "openssl" | tar -zx >> "$DIR/install.log" 2>&1

		echo -n " checking..."
		cd "$openssl_dir"
		RANLIB=$RANLIB $OPENSSL_CMD \
		--prefix="$INSTALL_DIR" \
		--openssldir="$INSTALL_DIR" \
		no-asm \
		no-hw \
		no-engine \
		$EXTRA_FLAGS >> "$DIR/install.log" 2>&1

		echo -n " compiling..."
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$openssl_dir"
	fi
	echo -n " installing..."
	make install_sw >> "$DIR/install.log" 2>&1
	cd ..
	echo " done!"
}

function build_curl {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--enable-static --disable-shared"
	else
		local EXTRA_FLAGS="--disable-static --enable-shared"
	fi

	write_library curl "$CURL_VERSION"
	local curl_dir="./curl-$CURL_VERSION"
	if cant_use_cache "$curl_dir"; then
		rm -rf "$curl_dir"
		write_download
		download_file "https://github.com/curl/curl/archive/$CURL_VERSION.tar.gz" "curl" | tar -zx >> "$DIR/install.log" 2>&1
		echo -n " checking..."
		cd "$curl_dir"
		./buildconf --force >> "$DIR/install.log" 2>&1
		RANLIB=$RANLIB ./configure --disable-dependency-tracking \
		--enable-ipv6 \
		--enable-optimize \
		--enable-http \
		--enable-ftp \
		--disable-dict \
		--enable-file \
		--without-librtmp \
		--disable-gopher \
		--disable-imap \
		--disable-pop3 \
		--disable-rtsp \
		--disable-smtp \
		--disable-telnet \
		--disable-tftp \
		--disable-ldap \
		--disable-ldaps \
		--without-libidn \
		--without-libidn2 \
		--without-brotli \
		--without-nghttp2 \
		--without-zstd \
		--with-zlib="$INSTALL_DIR" \
		--with-ssl="$INSTALL_DIR" \
		--enable-threaded-resolver \
		--prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS \
		$CONFIGURE_FLAGS >> "$DIR/install.log" 2>&1
		echo -n " compiling..."
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$curl_dir"
	fi

	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	cd ..
	echo " done!"
}

function build_yaml {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--disable-shared --enable-static"
	else
		local EXTRA_FLAGS="--enable-shared --disable-static"
	fi

	write_library yaml "$YAML_VERSION"
	local yaml_dir="./libyaml-$YAML_VERSION"
	if cant_use_cache "$yaml_dir"; then
		rm -rf "$yaml_dir"
		write_download
		download_file "https://github.com/yaml/libyaml/archive/$YAML_VERSION.tar.gz" "yaml" | tar -zx >> "$DIR/install.log" 2>&1
		cd "$yaml_dir"
		./bootstrap >> "$DIR/install.log" 2>&1

		echo -n " checking..."

		RANLIB=$RANLIB ./configure \
		--prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS \
		$CONFIGURE_FLAGS >> "$DIR/install.log" 2>&1
		sed -i=".backup" 's/ tests win32/ win32/g' Makefile
		echo -n " compiling..."
		make -j $THREADS all >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$yaml_dir"
	fi
	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	cd ..
	echo " done!"
}

function build_leveldb {
	write_library leveldb "$LEVELDB_VERSION"
	local leveldb_dir="./leveldb-$LEVELDB_VERSION"
	if cant_use_cache "$leveldb_dir"; then
		rm -rf "$leveldb_dir"
		write_download
		download_file "https://github.com/pmmp/leveldb/archive/$LEVELDB_VERSION.tar.gz" "leveldb" | tar -zx >> "$DIR/install.log" 2>&1
		#download_file "https://github.com/Mojang/leveldb-mcpe/archive/$LEVELDB_VERSION.tar.gz" | tar -zx >> "$DIR/install.log" 2>&1
		echo -n " checking..."
		cd "$leveldb_dir"
		if [ "$DO_STATIC" != "yes" ]; then
			local EXTRA_FLAGS="-DBUILD_SHARED_LIBS=ON"
		else
			local EXTRA_FLAGS=""
		fi
		cmake . \
			-DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
			-DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
			-DCMAKE_INSTALL_LIBDIR=lib \
			-DLEVELDB_BUILD_TESTS=OFF \
			-DLEVELDB_BUILD_BENCHMARKS=OFF \
			-DLEVELDB_SNAPPY=OFF \
			-DLEVELDB_ZSTD=OFF \
			-DLEVELDB_TCMALLOC=OFF \
			-DCMAKE_BUILD_TYPE=Release \
			$CMAKE_GLOBAL_EXTRA_FLAGS \
			$EXTRA_FLAGS \
			>> "$DIR/install.log" 2>&1
		echo -n " compiling..."
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$leveldb_dir"
	fi
	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	cd ..
	echo " done!"
}

function build_libpng {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--enable-shared=no --enable-static=yes"
	else
		local EXTRA_FLAGS="--enable-shared=yes --enable-static=no"
	fi

	write_library libpng "$LIBPNG_VERSION"
	local libpng_dir="./libpng-$LIBPNG_VERSION"
	if cant_use_cache "$libpng_dir"; then
		rm -rf "$libpng_dir"
		write_download
		download_file "https://sourceforge.net/projects/libpng/files/libpng16/$LIBPNG_VERSION/libpng-$LIBPNG_VERSION.tar.gz" "libpng" | tar -zx >> "$DIR/install.log" 2>&1
		echo -n " checking..."
		cd "$libpng_dir"
		LDFLAGS="$LDFLAGS -L${INSTALL_DIR}/lib" CPPFLAGS="$CPPFLAGS -I${INSTALL_DIR}/include" RANLIB=$RANLIB ./configure \
		--prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS \
		$CONFIGURE_FLAGS >> "$DIR/install.log" 2>&1
		echo -n " compiling..."
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$libpng_dir"
	fi
	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	cd ..
	echo " done!"
}

function build_libjpeg {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--enable-shared=no --enable-static=yes"
	else
		local EXTRA_FLAGS="--enable-shared=yes --enable-static=no"
	fi

	write_library libjpeg "$LIBJPEG_VERSION"
	local libjpeg_dir="./libjpeg-$LIBJPEG_VERSION"
	if cant_use_cache "$libjpeg_dir"; then
		rm -rf "$libjpeg_dir"
		write_download
		download_file "http://ijg.org/files/jpegsrc.v$LIBJPEG_VERSION.tar.gz" "libjpeg" | tar -zx >> "$DIR/install.log" 2>&1
		mv jpeg-$LIBJPEG_VERSION "$libjpeg_dir"
		echo -n " checking..."
		cd "$libjpeg_dir"
		LDFLAGS="$LDFLAGS -L${INSTALL_DIR}/lib" CPPFLAGS="$CPPFLAGS -I${INSTALL_DIR}/include" RANLIB=$RANLIB ./configure \
		--prefix="$INSTALL_DIR" \
		$EXTRA_FLAGS \
		$CONFIGURE_FLAGS >> "$DIR/install.log" 2>&1
		echo -n " compiling..."
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$libjpeg_dir"
	fi
	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	cd ..
	echo " done!"
}


function build_libxml2 {
	write_library libxml2 "$LIBXML_VERSION"
	local libxml2_dir="./libxml2-$LIBXML_VERSION"

	if cant_use_cache "$libxml2_dir"; then
		rm -rf "$libxml2_dir"
		write_download
		download_file "https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$LIBXML_VERSION/libxml2-v$LIBXML_VERSION.tar.gz" "libxml2" | tar -xz >> "$DIR/install.log" 2>&1
		mv libxml2-v$LIBXML_VERSION "$libxml2_dir"
		echo -n "checking... "
		cd "$libxml2_dir"
		if [ "$DO_STATIC" == "yes" ]; then
			local EXTRA_FLAGS="--enable-shared=no --enable-static=yes"
		else
			local EXTRA_FLAGS="--enable-shared=yes --enable-static=no"
		fi
		sed -i.bak 's{libtoolize --version{"$LIBTOOLIZE" --version{' autogen.sh #needed for glibtool on macos
		./autogen.sh --prefix="$INSTALL_DIR" \
			--without-iconv \
			--without-python \
			--without-lzma \
			--with-zlib="$INSTALL_DIR" \
			--config-cache \
			$EXTRA_FLAGS \
			$CONFIGURE_FLAGS >> "$DIR/install.log" 2>&1
		echo -n "compiling... "
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$libxml2_dir"
	fi
	echo -n "installing... "
	make install >> "$DIR/install.log" 2>&1
	cd ..
	echo "done!"
}

function build_libzip {
	#libzip
	if [ "$DO_STATIC" == "yes" ]; then
		local CMAKE_LIBZIP_EXTRA_FLAGS="-DBUILD_SHARED_LIBS=OFF"
	fi

	write_library libzip "$LIBZIP_VERSION"
	local libzip_dir="./libzip-$LIBZIP_VERSION"
	if cant_use_cache "$libzip_dir"; then
		rm -rf "$libzip_dir"
		write_download
		download_file "https://libzip.org/download/libzip-$LIBZIP_VERSION.tar.gz" "libzip" | tar -zx >> "$DIR/install.log" 2>&1
		echo -n " checking..."
		cd "$libzip_dir"

		#we're using OpenSSL for crypto
		cmake . \
			-DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
			-DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
			-DCMAKE_INSTALL_LIBDIR=lib \
			$CMAKE_LIBZIP_EXTRA_FLAGS \
			$CMAKE_GLOBAL_EXTRA_FLAGS \
			-DBUILD_TOOLS=OFF \
			-DBUILD_REGRESS=OFF \
			-DBUILD_EXAMPLES=OFF \
			-DBUILD_DOC=OFF \
			-DENABLE_BZIP2=OFF \
			-DENABLE_COMMONCRYPTO=OFF \
			-DENABLE_GNUTLS=OFF \
			-DENABLE_MBEDTLS=OFF \
			-DENABLE_LZMA=OFF \
			-DENABLE_ZSTD=OFF >> "$DIR/install.log" 2>&1
		echo -n " compiling..."
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$libzip_dir"
	fi
	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	cd ..
	echo " done!"
}

function build_sqlite3 {
	if [ "$DO_STATIC" == "yes" ]; then
		local EXTRA_FLAGS="--enable-static=yes --enable-shared=no"
	else
		local EXTRA_FLAGS="--enable-static=no --enable-shared=yes"
	fi

	write_library sqlite3 "$SQLITE3_VERSION"
	local sqlite3_dir="./sqlite3-$SQLITE3_VERSION"

	if cant_use_cache "$sqlite3_dir"; then
		rm -rf "$sqlite3_dir"
		write_download
		download_file "https://www.sqlite.org/$SQLITE3_YEAR/sqlite-autoconf-$SQLITE3_VERSION.tar.gz" "sqlite3" | tar -zx >> "$DIR/install.log" 2>&1
		mv sqlite-autoconf-$SQLITE3_VERSION "$sqlite3_dir" >> "$DIR/install.log" 2>&1
		echo -n " checking..."
		cd "$sqlite3_dir"
		LDFLAGS="$LDFLAGS -L${INSTALL_DIR}/lib" CPPFLAGS="$CPPFLAGS -I${INSTALL_DIR}/include" RANLIB=$RANLIB ./configure \
		--prefix="$INSTALL_DIR" \
		--disable-dependency-tracking \
		--enable-static-shell=no \
		$EXTRA_FLAGS \
		$CONFIGURE_FLAGS >> "$DIR/install.log" 2>&1
		echo -n " compiling..."
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$sqlite3_dir"
	fi
	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	cd ..
	echo " done!"
}

function build_libdeflate {
	write_library libdeflate "$LIBDEFLATE_VERSION"
	local libdeflate_dir="./libdeflate-$LIBDEFLATE_VERSION"

	if [ "$DO_STATIC" == "yes" ]; then
		local CMAKE_LIBDEFLATE_EXTRA_FLAGS="-DLIBDEFLATE_BUILD_STATIC_LIB=ON -DLIBDEFLATE_BUILD_SHARED_LIB=OFF"
	else
		local CMAKE_LIBDEFLATE_EXTRA_FLAGS="-DLIBDEFLATE_BUILD_STATIC_LIB=OFF -DLIBDEFLATE_BUILD_SHARED_LIB=ON"
	fi

	if cant_use_cache "$libdeflate_dir"; then
		rm -rf "$libdeflate_dir"
		write_download
		download_file "https://github.com/ebiggers/libdeflate/archive/$LIBDEFLATE_VERSION.tar.gz" "libdeflate" | tar -zx >> "$DIR/install.log" 2>&1
		cd "$libdeflate_dir"
		echo -n " checking..."
		cmake . \
			-DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
			-DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
			-DCMAKE_INSTALL_LIBDIR=lib \
			$CMAKE_GLOBAL_EXTRA_FLAGS \
			-DLIBDEFLATE_BUILD_GZIP=OFF \
			$CMAKE_LIBDEFLATE_EXTRA_FLAGS >> "$DIR/install.log" 2>&1
		echo -n " compiling..."
		make -j $THREADS >> "$DIR/install.log" 2>&1 && mark_cache
	else
		write_caching
		cd "$libdeflate_dir"
	fi
	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	cd ..
	echo " done!"
}

cd "$LIB_BUILD_DIR"

build_zlib
build_gmp
build_openssl
build_curl
build_yaml
build_leveldb
if [ "$COMPILE_GD" == "yes" ]; then
	build_libpng
	build_libjpeg
	HAS_GD="--enable-gd"
	HAS_LIBJPEG="--with-jpeg"
else
	HAS_GD=""
	HAS_LIBJPEG=""
fi

build_libxml2
build_libzip
build_sqlite3
build_libdeflate

# PECL libraries

# 1: extension name
# 2: extension version
# 3: URL to get .tar.gz from
# 4: Name of extracted directory to move
function get_extension_tar_gz {
	echo -n "  $1: downloading $2..."
	download_file "$3" "php-ext-$1" | tar -zx >> "$DIR/install.log" 2>&1
	mv "$4" "$BUILD_DIR/php/ext/$1"
	echo " done!"
}

# 1: extension name
# 2: extension version
# 3: github user name
# 4: github repo name
# 5: version prefix (optional)
function get_github_extension {
	get_extension_tar_gz "$1" "$2" "https://github.com/$3/$4/archive/$5$2.tar.gz" "$4-$2"
}

# 1: extension name
# 2: extension version
function get_pecl_extension {
	get_extension_tar_gz "$1" "$2" "http://pecl.php.net/get/$1-$2.tgz" "$1-$2"
}

cd "$BUILD_DIR/php"
echo "[PHP] Downloading additional extensions..."

get_github_extension "pthreads" "$EXT_PTHREADS_VERSION" "pmmp" "pthreads" #"v" needed for release tags because github removes the "v"
#get_pecl_extension "pthreads" "$EXT_PTHREADS_VERSION"

get_github_extension "yaml" "$EXT_YAML_VERSION" "php" "pecl-file_formats-yaml"
#get_pecl_extension "yaml" "$EXT_YAML_VERSION"

get_github_extension "igbinary" "$EXT_IGBINARY_VERSION" "igbinary" "igbinary"

get_github_extension "recursionguard" "$EXT_RECURSIONGUARD_VERSION" "pmmp" "ext-recursionguard"

echo -n "  crypto: downloading $EXT_CRYPTO_VERSION..."
git clone https://github.com/bukka/php-crypto.git "$BUILD_DIR/php/ext/crypto" >> "$DIR/install.log" 2>&1
cd "$BUILD_DIR/php/ext/crypto"
git checkout "$EXT_CRYPTO_VERSION" >> "$DIR/install.log" 2>&1
git submodule update --init --recursive >> "$DIR/install.log" 2>&1
cd "$BUILD_DIR"
echo " done!"

get_github_extension "leveldb" "$EXT_LEVELDB_VERSION" "pmmp" "php-leveldb"

get_github_extension "chunkutils2" "$EXT_CHUNKUTILS2_VERSION" "pmmp" "ext-chunkutils2"

get_github_extension "libdeflate" "$EXT_LIBDEFLATE_VERSION" "pmmp" "ext-libdeflate"

get_github_extension "morton" "$EXT_MORTON_VERSION" "pmmp" "ext-morton"

get_github_extension "xxhash" "$EXT_XXHASH_VERSION" "pmmp" "ext-xxhash"

echo -n "[PHP]"

if [ "$DO_OPTIMIZE" != "no" ]; then
	echo -n " enabling optimizations..."
	PHP_OPTIMIZATION="--enable-inline-optimization "
else
	PHP_OPTIMIZATION="--disable-inline-optimization "
fi
echo -n " checking..."
cd php
rm -f ./aclocal.m4 >> "$DIR/install.log" 2>&1
rm -rf ./autom4te.cache/ >> "$DIR/install.log" 2>&1
rm -f ./configure >> "$DIR/install.log" 2>&1

./buildconf --force >> "$DIR/install.log" 2>&1

#hack for curl with pkg-config (ext/curl doesn't give --static to pkg-config on static builds)
if [ "$DO_STATIC" == "yes" ]; then
	if [ -z "$PKG_CONFIG" ]; then
		PKG_CONFIG="$(which pkg-config)" || true
	fi
	if [ ! -z "$PKG_CONFIG" ]; then
		#only export this if pkg-config exists, otherwise leave it (it'll fall back to curl-config)

		echo '#!/bin/sh' > "$BUILD_DIR/pkg-config-wrapper"
		echo 'exec '$PKG_CONFIG' "$@" --static' >> "$BUILD_DIR/pkg-config-wrapper"
		chmod +x "$BUILD_DIR/pkg-config-wrapper"
		export PKG_CONFIG="$BUILD_DIR/pkg-config-wrapper"
	fi
fi


if [ "$IS_CROSSCOMPILE" == "yes" ]; then
	sed -i=".backup" 's/pthreads_working=no/pthreads_working=yes/' ./configure
	if [ "$IS_WINDOWS" != "yes" ]; then
		if [ "$COMPILE_FOR_ANDROID" == "no" ]; then
			export LIBS="$LIBS -lpthread -ldl -lresolv"
		else
			export LIBS="$LIBS -lpthread -lresolv"
		fi
	else
		export LIBS="$LIBS -lpthread"
	fi

	mv ext/mysqlnd/config9.m4 ext/mysqlnd/config.m4
	sed  -i=".backup" "s{ext/mysqlnd/php_mysqlnd_config.h{config.h{" ext/mysqlnd/mysqlnd_portability.h
elif [ "$DO_STATIC" == "yes" ]; then
	export LIBS="$LIBS -ldl"
fi

if [ "$IS_WINDOWS" != "yes" ]; then
	HAVE_PCNTL="--enable-pcntl"
else
	HAVE_PCNTL="--disable-pcntl"
	cp -f ./win32/build/config.* ./main >> "$DIR/install.log" 2>&1
	sed 's:@PREFIX@:$DIR/bin/php7:' ./main/config.w32.h.in > ./wmain/config.w32.h 2>> "$DIR/install.log"
fi

if [[ "$(uname -s)" == "Darwin" ]] && [[ "$IS_CROSSCOMPILE" != "yes" ]]; then
	sed -i=".backup" 's/flock_type=unknown/flock_type=bsd/' ./configure
	export EXTRA_CFLAGS=-lresolv
fi

if [[ "$COMPILE_DEBUG" == "yes" ]]; then
	HAS_DEBUG="--enable-debug"
else
	HAS_DEBUG="--disable-debug"
fi

if [ "$FSANITIZE_OPTIONS" != "" ]; then
	CFLAGS="$CFLAGS -fsanitize=$FSANITIZE_OPTIONS -fno-omit-frame-pointer"
	CXXFLAGS="$CXXFLAGS -fsanitize=$FSANITIZE_OPTIONS -fno-omit-frame-pointer"
	LDFLAGS="-fsanitize=$FSANITIZE_OPTIONS $LDFLAGS"
fi

RANLIB=$RANLIB CFLAGS="$CFLAGS $FLAGS_LTO" CXXFLAGS="$CXXFLAGS $FLAGS_LTO" LDFLAGS="$LDFLAGS $FLAGS_LTO" ./configure $PHP_OPTIMIZATION --prefix="$INSTALL_DIR" \
--exec-prefix="$INSTALL_DIR" \
--with-curl \
--with-zlib \
--with-zlib \
--with-gmp \
--with-yaml \
--with-openssl \
--with-zip \
--with-libdeflate \
$HAS_LIBJPEG \
$HAS_GD \
--with-leveldb="$INSTALL_DIR" \
--without-readline \
$HAS_DEBUG \
--enable-chunkutils2 \
--enable-morton \
--enable-mbstring \
--disable-mbregex \
--enable-calendar \
--enable-pthreads \
--enable-fileinfo \
--with-libxml \
--enable-xml \
--enable-dom \
--enable-simplexml \
--enable-xmlreader \
--enable-xmlwriter \
--disable-cgi \
--disable-phpdbg \
--disable-session \
--without-pear \
--without-iconv \
--with-pdo-sqlite \
--with-pdo-mysql \
--with-pic \
--enable-phar \
--enable-ctype \
--enable-sockets \
--enable-shared=no \
--enable-static=yes \
--enable-shmop \
--enable-zts \
--disable-short-tags \
$HAVE_PCNTL \
$HAVE_MYSQLI \
--enable-bcmath \
--enable-cli \
--enable-ftp \
--enable-opcache=$HAVE_OPCACHE \
--enable-opcache-jit=$HAVE_OPCACHE \
--enable-igbinary \
--with-crypto \
--enable-recursionguard \
--enable-xxhash \
$HAVE_VALGRIND \
$CONFIGURE_FLAGS >> "$DIR/install.log" 2>&1
echo -n " compiling..."
if [ "$COMPILE_FOR_ANDROID" == "yes" ]; then
	sed -i=".backup" 's/-export-dynamic/-all-static/g' Makefile
fi
sed -i=".backup" 's/PHP_BINARIES. pharcmd$/PHP_BINARIES)/g' Makefile
sed -i=".backup" 's/install-programs install-pharcmd$/install-programs/g' Makefile

if [[ "$DO_STATIC" == "yes" ]]; then
	sed -i=".backup" 's/--mode=link $(CC)/--mode=link $(CXX)/g' Makefile
fi

make -j $THREADS >> "$DIR/install.log" 2>&1
echo -n " installing..."
make install >> "$DIR/install.log" 2>&1

function relativize_macos_library_paths {
	IFS=$'\n' OTOOL_OUTPUT=($(otool -L "$1"))

	for (( i=0; i<${#OTOOL_OUTPUT[@]}; i++ ))
		do
		CURRENT_DYLIB_NAME=$(echo ${OTOOL_OUTPUT[$i]} | sed 's# (compatibility version .*##' | xargs)
		if [[ "$CURRENT_DYLIB_NAME" == "$INSTALL_DIR/"* ]]; then
			NEW_DYLIB_NAME=$(echo "$CURRENT_DYLIB_NAME" | sed "s{$INSTALL_DIR{@loader_path/..{" | xargs)
			install_name_tool -change "$CURRENT_DYLIB_NAME" "$NEW_DYLIB_NAME" "$1" >> "$DIR/install.log" 2>&1
		elif [[ "$CURRENT_DYLIB_NAME" != "/usr/lib/"* ]] && [[ "$CURRENT_DYLIB_NAME" != "/System/"* ]] && [[ "$CURRENT_DYLIB_NAME" != "@loader_path"* ]] && [[ "$CURRENT_DYLIB_NAME" != "@rpath"* ]]; then
			echo "[ERROR] Detected linkage to non-local non-system library $CURRENT_DYLIB_NAME by $1"
			exit 1
		fi
	done
}

function relativize_macos_all_libraries_paths {
	set +e
	for _library in $(ls "$INSTALL_DIR/lib/"*".dylib"); do
		relativize_macos_library_paths "$_library"
	done
	set -e
}

if [[ "$(uname -s)" == "Darwin" ]] && [[ "$IS_CROSSCOMPILE" != "yes" ]]; then
	set +e
	install_name_tool -delete_rpath "$INSTALL_DIR/lib" "$INSTALL_DIR/bin/php" >> "$DIR/install.log" 2>&1

	relativize_macos_library_paths "$INSTALL_DIR/bin/php"

	relativize_macos_all_libraries_paths
	set -e
fi

echo -n " generating php.ini..."
trap - DEBUG
TIMEZONE=$(date +%Z)
echo "memory_limit=1024M" >> "$INSTALL_DIR/bin/php.ini"
echo "date.timezone=$TIMEZONE" >> "$INSTALL_DIR/bin/php.ini"
echo "short_open_tag=0" >> "$INSTALL_DIR/bin/php.ini"
echo "asp_tags=0" >> "$INSTALL_DIR/bin/php.ini"
echo "phar.require_hash=1" >> "$INSTALL_DIR/bin/php.ini"
echo "igbinary.compact_strings=0" >> "$INSTALL_DIR/bin/php.ini"
if [[ "$COMPILE_DEBUG" == "yes" ]]; then
	echo "zend.assertions=1" >> "$INSTALL_DIR/bin/php.ini"
else
	echo "zend.assertions=-1" >> "$INSTALL_DIR/bin/php.ini"
fi
echo "error_reporting=-1" >> "$INSTALL_DIR/bin/php.ini"
echo "display_errors=1" >> "$INSTALL_DIR/bin/php.ini"
echo "display_startup_errors=1" >> "$INSTALL_DIR/bin/php.ini"
echo "recursionguard.enabled=0 ;disabled due to minor performance impact, only enable this if you need it for debugging" >> "$INSTALL_DIR/bin/php.ini"

if [ "$HAVE_OPCACHE" == "yes" ]; then
	echo "zend_extension=opcache.so" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.enable=1" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.enable_cli=1" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.save_comments=1" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.validate_timestamps=1" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.revalidate_freq=0" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.file_update_protection=0" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.optimization_level=0x7FFEBFFF ;https://github.com/php/php-src/blob/53c1b485741f31a17b24f4db2b39afeb9f4c8aba/ext/opcache/Optimizer/zend_optimizer.h" >> "$INSTALL_DIR/bin/php.ini"
	echo "" >> "$INSTALL_DIR/bin/php.ini"
	echo "; ---- ! WARNING ! ----" >> "$INSTALL_DIR/bin/php.ini"
	echo "; JIT can provide big performance improvements, but as of PHP 8.0.8 it is still unstable. For this reason, it is disabled by default." >> "$INSTALL_DIR/bin/php.ini"
	echo "; Enable it at your own risk. See https://www.php.net/manual/en/opcache.configuration.php#ini.opcache.jit for possible options." >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.jit=off" >> "$INSTALL_DIR/bin/php.ini"
	echo "opcache.jit_buffer_size=128M" >> "$INSTALL_DIR/bin/php.ini"
fi
if [ "$COMPILE_TARGET" == "mac-"* ]; then
	#we don't have permission to allocate executable memory on macOS due to not being codesigned
	#workaround this for now by disabling PCRE JIT
	echo "" >> "$INSTALL_DIR/bin/php.ini"
	echo "pcre.jit=off" >> "$INSTALL_DIR/bin/php.ini"
fi

echo " done!"

if [[ "$HAVE_XDEBUG" == "yes" ]]; then
	get_github_extension "xdebug" "$EXT_XDEBUG_VERSION" "xdebug" "xdebug"
	echo -n "[xdebug] checking..."
	cd "$BUILD_DIR/php/ext/xdebug"
	"$INSTALL_DIR/bin/phpize" >> "$DIR/install.log" 2>&1
	./configure --with-php-config="$INSTALL_DIR/bin/php-config" >> "$DIR/install.log" 2>&1
	echo -n " compiling..."
	make -j4 >> "$DIR/install.log" 2>&1
	echo -n " installing..."
	make install >> "$DIR/install.log" 2>&1
	echo "" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo ";WARNING: When loaded, xdebug 3.2.0 will cause segfaults whenever an uncaught error is thrown, even if xdebug.mode=off. Load it at your own risk." >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo ";zend_extension=xdebug.so" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo ";https://xdebug.org/docs/all_settings#mode" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo "xdebug.mode=off" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo "xdebug.start_with_request=yes" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo ";The following overrides allow profiler, gc stats and traces to work correctly in ZTS" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo "xdebug.profiler_output_name=cachegrind.%s.%p.%r" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo "xdebug.gc_stats_output_name=gcstats.%s.%p.%r" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo "xdebug.trace_output_name=trace.%s.%p.%r" >> "$INSTALL_DIR/bin/php.ini" 2>&1
	echo " done!"
	write_out INFO "Xdebug is included, but disabled by default. To enable it, change 'xdebug.mode' in your php.ini file."
fi

cd "$DIR"
if [ "$DO_CLEANUP" == "yes" ]; then
	echo -n "[INFO] Cleaning up..."
	rm -r -f "$BUILD_DIR" >> "$DIR/install.log" 2>&1
	rm -f "$INSTALL_DIR/bin/curl"* >> "$DIR/install.log" 2>&1
	rm -f "$INSTALL_DIR/bin/curl-config"* >> "$DIR/install.log" 2>&1
	rm -f "$INSTALL_DIR/bin/c_rehash"* >> "$DIR/install.log" 2>&1
	rm -f "$INSTALL_DIR/bin/openssl"* >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/man" >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/share/man" >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/php" >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/misc" >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/lib/"*.a >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/lib/"*.la >> "$DIR/install.log" 2>&1
	rm -r -f "$INSTALL_DIR/include" >> "$DIR/install.log" 2>&1
	echo " done!"
fi

date >> "$DIR/install.log" 2>&1
echo "[PocketMine] You should start the server now using \"./start.sh\"."
echo "[PocketMine] If it doesn't work, please send the \"install.log\" file to the Bug Tracker."
