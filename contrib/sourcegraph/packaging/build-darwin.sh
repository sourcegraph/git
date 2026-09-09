#!/bin/sh
set -eu

SOURCE_TAG=v2.55.0
SOURCE_COMMIT=e9019fcafe0040228b8631c30f97ae1adb61bcdc
RELEASE_VERSION=v2.55.0-1
PCRE2_VERSION=10.48
PCRE2_SHA256=b6c68fdf6f3ac31388b50aa89ff0fc49c00c987c16e7b5146491d12003f2c8ed

test "$(uname -s)" = Darwin && test "$(uname -m)" = arm64 || {
	echo 'error: the Darwin archive must be built on an arm64 Mac' >&2
	exit 1
}

root=$(git rev-parse --show-toplevel)
output=${1:-"$root/artifacts"}
RECIPE_COMMIT=$(git -C "$root" rev-parse HEAD)
actual=$(git -C "$root" rev-parse "$SOURCE_TAG^{commit}")
test "$actual" = "$SOURCE_COMMIT" || {
	echo "error: $SOURCE_TAG resolved to $actual, expected $SOURCE_COMMIT" >&2
	exit 1
}

mkdir -p "$output"
output=$(cd "$output" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

# Resolve the non-Apple tools before replacing the inherited PATH. Sourcegraph
# shells may export a Nix SDK and library search paths which must not influence
# a redistributable Mac build.
rust_dir=$(dirname "$(command -v rustc)")
cargo_dir=$(dirname "$(command -v cargo)")
gtar_dir=$(dirname "$(command -v gtar)")
unset SDKROOT CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH \
	LD_LIBRARY_PATH DYLD_LIBRARY_PATH PKG_CONFIG_PATH CFLAGS CPPFLAGS LDFLAGS \
	CC CXX AR RANLIB
if test -n "${SOURCEGRAPH_GIT_DEVELOPER_DIR:-}"
then
	DEVELOPER_DIR=$SOURCEGRAPH_GIT_DEVELOPER_DIR
else
	selected_developer_dir=$(/usr/bin/xcode-select -p)
	case "$selected_developer_dir" in
		/Applications/*.app/Contents/Developer|/Library/Developer/CommandLineTools)
			DEVELOPER_DIR=$selected_developer_dir ;;
		*)
			if test -d /Applications/Xcode.app/Contents/Developer
			then
				DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
			else
				echo "error: xcode-select resolved non-Apple developer directory: $selected_developer_dir" >&2
				echo 'set SOURCEGRAPH_GIT_DEVELOPER_DIR to an Apple Xcode or CommandLineTools directory' >&2
				exit 1
			fi ;;
	esac
fi
export DEVELOPER_DIR
SDKROOT=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
export SDKROOT
MACOSX_DEPLOYMENT_TARGET=${SOURCEGRAPH_GIT_DEPLOYMENT_TARGET:-14.0}
export MACOSX_DEPLOYMENT_TARGET
CC=$(/usr/bin/xcrun --find clang)
AR=$(/usr/bin/xcrun --find ar)
RANLIB=$(/usr/bin/xcrun --find ranlib)
export CC AR RANLIB
PATH="$rust_dir:$cargo_dir:$gtar_dir:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

# Detect an invalid or incomplete selected SDK before doing the dependency build.
printf '#include <zlib.h>\n' | "$CC" -isysroot "$SDKROOT" -x c -fsyntax-only - || {
	echo "error: selected Xcode SDK cannot compile against zlib: $SDKROOT" >&2
	exit 1
}

git -C "$root" archive "$SOURCE_COMMIT" | tar -x -C "$work"
mkdir -p "$work/contrib/sourcegraph"
cp -R "$root/contrib/sourcegraph/packaging" "$work/contrib/sourcegraph/"

pcre_archive="$work/pcre2-$PCRE2_VERSION.tar.bz2"
/usr/bin/curl -fL --retry 3 \
	"https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.bz2" \
	-o "$pcre_archive"
printf '%s  %s\n' "$PCRE2_SHA256" "$pcre_archive" | /usr/bin/shasum -a 256 -c -
tar -xjf "$pcre_archive" -C "$work"
pcre_prefix="$work/pcre2-install"
(
	cd "$work/pcre2-$PCRE2_VERSION"
	./configure --prefix="$pcre_prefix" --disable-shared --enable-static --enable-jit
	/usr/bin/make -j"$(getconf _NPROCESSORS_ONLN)"
	/usr/bin/make install
)

(
	cd "$work"
	SOURCE_DATE_EPOCH=$(git -C "$root" show -s --format=%ct "$SOURCE_COMMIT") \
	SOURCE_COMMIT="$SOURCE_COMMIT" SOURCE_TAG="$SOURCE_TAG" \
	RECIPE_COMMIT="$RECIPE_COMMIT" RELEASE_VERSION="$RELEASE_VERSION" \
	PCRE2_PREFIX="$pcre_prefix" \
	PCRE2_LICENSE="$work/pcre2-$PCRE2_VERSION/LICENCE.md" \
	SOURCE_BUILD_ROOT="$work" \
	contrib/sourcegraph/packaging/build-from-source.sh darwin-arm64 "$output"
)
