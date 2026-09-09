#!/bin/sh
set -eu

prefix=${1:?usage: verify-darwin-dependencies.sh PREFIX}
: "${MACOSX_DEPLOYMENT_TARGET:?MACOSX_DEPLOYMENT_TARGET is required}"
: "${SOURCE_BUILD_ROOT:?SOURCE_BUILD_ROOT is required}"
test -s "$prefix/LICENSES/Git-COPYING"
test -s "$prefix/LICENSES/PCRE2-LICENCE"
status_file=$(mktemp)
trap 'rm -f "$status_file"' EXIT HUP INT TERM
find "$prefix/bin" "$prefix/libexec" -type f -perm -111 | while IFS= read -r executable
do
	file "$executable" | grep -q 'Mach-O' || continue
	file "$executable" | grep -q 'arm64' || {
		echo "error: non-arm64 executable: $executable" >&2
		echo failed >>"$status_file"
	}
	minos=$(otool -l "$executable" | awk \
		'/cmd LC_BUILD_VERSION/ { found = 1; next } found && $1 == "minos" { print $2; exit }')
	test "$minos" = "$MACOSX_DEPLOYMENT_TARGET" || {
		echo "error: $executable targets macOS $minos, expected $MACOSX_DEPLOYMENT_TARGET" >&2
		echo failed >>"$status_file"
	}
	for build_path in "$SOURCE_BUILD_ROOT" "$(dirname "$prefix")"
	do
		if strings "$executable" | grep -F "$build_path" >/dev/null
		then
			echo "error: build path embedded in $executable: $build_path" >&2
			echo failed >>"$status_file"
		fi
	done
	otool -L "$executable" | tail -n +2 | awk '{ print $1 }' | while IFS= read -r library
	do
		case "$library" in
			/System/Library/*|/usr/lib/*) ;;
			*) echo "error: non-system dependency in $executable: $library" >&2; echo failed >>"$status_file" ;;
		esac
	done
	codesign --verify --verbose "$executable" 2>/dev/null || codesign --force --sign - "$executable"
done
test ! -s "$status_file"
