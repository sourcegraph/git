#!/bin/sh
set -eu

prefix=${1:?usage: build-zlib-ng.sh PREFIX}
version=2.3.3
source_commit=12731092979c6d07f42da27da673a9f6c7b13586
source_sha256=a0d2a5d122c84b56a793a1553a9c3327fb2eb7469bf7a86b79e3c7be5d92e8d6

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cat >"$work/SOURCE-INFO" <<EOF
zlib_ng_version=$version
zlib_ng_source_commit=$source_commit
zlib_ng_source_sha256=$source_sha256
zlib_ng_recipe=1
EOF

if test -f "$prefix/include/zlib-ng.h" &&
	test -f "$prefix/lib/libz-ng.a" &&
	test -f "$prefix/LICENSE.md" &&
	cmp -s "$work/SOURCE-INFO" "$prefix/SOURCE-INFO"
then
	echo "zlib-ng $version is already installed."
	exit 0
fi

echo "Building zlib-ng $version..."
curl -fsSL --retry 3 \
	"https://github.com/zlib-ng/zlib-ng/archive/$source_commit.tar.gz" \
	-o "$work/zlib-ng.tar.gz"
printf '%s  %s\n' "$source_sha256" "$work/zlib-ng.tar.gz" |
	shasum -a 256 -c -
mkdir "$work/source"
tar -xzf "$work/zlib-ng.tar.gz" -C "$work/source" --strip-components=1
mkdir -p "$(dirname "$prefix")"
rm -rf "$prefix"
(
	cd "$work/source"
	./configure --static --prefix="$prefix"
	"${MAKE:-make}" -j"$(getconf _NPROCESSORS_ONLN)"
	"${MAKE:-make}" install
)
cp "$work/source/LICENSE.md" "$prefix/LICENSE.md"
cp "$work/SOURCE-INFO" "$prefix/SOURCE-INFO"
