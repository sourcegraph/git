#!/bin/sh
set -eu

platform=${1:?usage: build-from-source.sh PLATFORM [OUTPUT]}
output=${2:-/out}
: "${SOURCE_COMMIT:?SOURCE_COMMIT is required}"
: "${SOURCE_TAG:?SOURCE_TAG is required}"
: "${RECIPE_COMMIT:?RECIPE_COMMIT is required}"
: "${RELEASE_VERSION:?RELEASE_VERSION is required}"
: "${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is required}"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT HUP INT TERM

case "$platform" in
	linux-amd64)
		test "$(uname -s)-$(uname -m)" = Linux-x86_64
		make_options='RUNTIME_PREFIX=YesPlease USE_LIBPCRE2=YesPlease INSTALL_STRIP=-s NO_INSTALL_HARDLINKS=YesPlease'
		;;
	darwin-arm64)
		test "$(uname -s)-$(uname -m)" = Darwin-arm64
		# Force the SDK-provided iconv instead of config.mak.uname's Homebrew
		# workaround on recent Darwin. Expose only the locally built PCRE2
		# static archive so no package-manager path survives the installation.
		pcre_prefix=${PCRE2_PREFIX:?PCRE2_PREFIX is required on Darwin}
		test -f "$pcre_prefix/lib/libpcre2-8.a"
		static_pcre="$stage/static-pcre2"
		mkdir "$static_pcre"
		ln -s "$pcre_prefix/include" "$static_pcre/include"
		mkdir "$static_pcre/lib"
		cp "$pcre_prefix/lib/libpcre2-8.a" "$static_pcre/lib/"
		make_options="RUNTIME_PREFIX=YesPlease USE_LIBPCRE2=YesPlease \
			LIBPCREDIR=$static_pcre ICONVDIR=/usr \
			INSTALL_STRIP=-s NO_GETTEXT=YesPlease NO_INSTALL_HARDLINKS=YesPlease \
			USE_HOMEBREW_LIBICONV= NEEDS_GOOD_LIBICONV="
		;;
	*) echo "error: unsupported platform: $platform" >&2; exit 1 ;;
esac

prefix="$stage/git-sourcegraph"
mkdir -p "$prefix" "$output"

# Do not let a caller's prior build flags leak into the release artifact.
make clean
# shellcheck disable=SC2086
make -j"$(getconf _NPROCESSORS_ONLN)" $make_options \
	prefix=/ sysconfdir=/etc GIT_VERSION=2.55.0 \
	GIT_BUILT_FROM_COMMIT="$SOURCE_COMMIT" all
# shellcheck disable=SC2086
make $make_options prefix=/ sysconfdir=/etc GIT_VERSION=2.55.0 \
	GIT_BUILT_FROM_COMMIT="$SOURCE_COMMIT" DESTDIR="$prefix" install

mkdir "$prefix/LICENSES"
cp COPYING "$prefix/LICENSES/Git-COPYING"

if test "$platform" = darwin-arm64
then
	pcre2_license=${PCRE2_LICENSE:?PCRE2_LICENSE is required on Darwin}
	test -f "$pcre2_license" || {
		echo "error: PCRE2 license notice not found: $pcre2_license" >&2
		exit 1
	}
	cp "$pcre2_license" "$prefix/LICENSES/PCRE2-LICENCE"
	# The keychain helper is intentionally included in the full Mac install.
	# shellcheck disable=SC2086
	make $make_options prefix=/ sysconfdir=/etc GIT_VERSION=2.55.0 \
		GIT_BUILT_FROM_COMMIT="$SOURCE_COMMIT" DESTDIR="$prefix" \
		install-git-credential-osxkeychain
	contrib/sourcegraph/packaging/verify-darwin-dependencies.sh "$prefix"
else
	contrib/sourcegraph/packaging/bundle-linux-libraries.sh "$prefix"
fi

{
	echo "release_version=$RELEASE_VERSION"
	echo "source_tag=$SOURCE_TAG"
	echo "source_commit=$SOURCE_COMMIT"
	echo "recipe_commit=$RECIPE_COMMIT"
	echo "platform=$platform"
	echo "source_date_epoch=$SOURCE_DATE_EPOCH"
	echo "git_version=$($prefix/bin/git --version)"
	echo "git_build_options=$($prefix/bin/git version --build-options | tr '\n' ';')"
	echo "build_uname=$(uname -a)"
	echo "cc_version=$(cc --version | head -1)"
	echo "rustc_version=$(rustc --version)"
	echo "cargo_version=$(cargo --version)"
	if command -v dpkg-query >/dev/null 2>&1
	then
		echo 'builder_image=debian:12@sha256:6ebd97fa83deb272194a2cf015b3d26a4d538e9ad3a7a79d544c8af5b0a01443'
		echo 'build_packages_begin'
		dpkg-query -W -f='${Package}=${Version}\n' | LC_ALL=C sort
		echo 'build_packages_end'
	else
		echo "xcode_version=$(xcodebuild -version | tr '\n' ';')"
		echo 'pcre2_version=10.48'
		echo 'pcre2_source_sha256=b6c68fdf6f3ac31388b50aa89ff0fc49c00c987c16e7b5146491d12003f2c8ed'
		echo "macosx_deployment_target=${MACOSX_DEPLOYMENT_TARGET:-unset}"
	fi
} >"$prefix/BUILD-INFO"

archive="git-sourcegraph-${RELEASE_VERSION}-${platform}.tar.gz"
tar_command=tar
test "$platform" != darwin-arm64 || tar_command=${GTAR:-gtar}
COPYFILE_DISABLE=1 TZ=UTC "$tar_command" --sort=name --mtime="@$SOURCE_DATE_EPOCH" \
	--owner=0 --group=0 --numeric-owner -czf "$output/$archive" -C "$stage" git-sourcegraph
(cd "$output" && shasum -a 256 "$archive" >"$archive.sha256")
echo "$output/$archive"
