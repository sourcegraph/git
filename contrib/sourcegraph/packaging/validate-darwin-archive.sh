#!/bin/sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$script_dir/release.sh"

archive=${1:?usage: validate-darwin-archive.sh ARCHIVE}
test "$(uname -s)-$(uname -m)" = Darwin-arm64
expected_recipe=$(git -C "$script_dir" rev-parse HEAD)

archive_dir=$(CDPATH= cd "$(dirname "$archive")" && pwd)
archive_name=$(basename "$archive")
(cd "$archive_dir" && shasum -a 256 -c "$archive_name.sha256")

work=$(mktemp -d)
status_file=$(mktemp)
trap 'rm -rf "$work" "$status_file"' EXIT HUP INT TERM

roots=$(tar -tzf "$archive" | sed 's,/.*,,' | LC_ALL=C sort -u)
test "$roots" = git-sourcegraph

validate_prefix() {
	prefix=$1
	git="$prefix/bin/git"
	test -s "$prefix/LICENSES/Git-COPYING"
	test -s "$prefix/LICENSES/PCRE2-LICENCE"
	test "$("$git" --version)" = "git version $GIT_VERSION"
	build_options=$("$git" version --build-options)
	printf '%s\n' "$build_options" | grep -F "built from commit: $SOURCE_COMMIT"
	printf '%s\n' "$build_options" | grep -F 'rust: enabled'
	grep -Fx "release_version=$RELEASE_VERSION" "$prefix/BUILD-INFO"
	grep -Fx "upstream_version=$UPSTREAM_VERSION" "$prefix/BUILD-INFO"
	grep -Fx "release_revision=$RELEASE_REVISION" "$prefix/BUILD-INFO"
	grep -Fx "source_tag=$SOURCE_TAG" "$prefix/BUILD-INFO"
	grep -Fx "source_commit=$SOURCE_COMMIT" "$prefix/BUILD-INFO"
	grep -Fx "recipe_commit=$expected_recipe" "$prefix/BUILD-INFO"
	test "$("$git" --exec-path)" = "$prefix/libexec/git-core"
	test "$("$git" --html-path)" = "$prefix/share/doc/git-doc"

	home="$work/home"
	mkdir -p "$home"
	GIT_CONFIG_SYSTEM=/dev/null HOME="$home" "$git" init -q "$work/repository"
	test -f "$work/repository/.git/hooks/applypatch-msg.sample"
	printf 'needle\n' >"$work/repository/content"
	GIT_CONFIG_SYSTEM=/dev/null HOME="$home" "$git" -C "$work/repository" add content
	GIT_CONFIG_SYSTEM=/dev/null HOME="$home" "$git" -C "$work/repository" grep -P 'n(?=eedle)'
	rm -rf "$work/repository"
}

for location in 'first prefix' second/original
do
	mkdir -p "$work/$location"
	tar -xzf "$archive" -C "$work/$location" --strip-components=1
	validate_prefix "$work/$location"
done

mkdir -p "$work/second/moved"
mv "$work/second/original" "$work/second/moved/prefix"
validate_prefix "$work/second/moved/prefix"
prefix="$work/second/moved/prefix"
GIT_CONFIG_SYSTEM=/dev/null HOME="$work/home" "$prefix/bin/git" ls-remote \
	https://github.com/git/git.git HEAD | grep -E '^[0-9a-f]{40}[[:space:]]+HEAD$'

mkdir "$work/external"
cat >"$work/external/git-lfs" <<EOF
#!/bin/sh
echo external-lfs-ok
EOF
chmod +x "$work/external/git-lfs"
PATH="$work/external:$PATH" "$prefix/bin/git" lfs version | grep -Fx external-lfs-ok

macho_count=$(find "$prefix/bin" "$prefix/libexec" -type f -perm -111 \
	-exec file {} + | grep -c 'Mach-O' || :)
test "$macho_count" -gt 0
find "$prefix/bin" "$prefix/libexec" -type f -perm -111 | while IFS= read -r executable
do
	file "$executable" | grep -q 'Mach-O' || continue
	file "$executable" | grep -q 'arm64' || {
		echo "error: non-arm64 executable: $executable" >&2
		echo failed >>"$status_file"
	}
	minos=$(otool -l "$executable" | awk \
		'/cmd LC_BUILD_VERSION/ { found = 1; next } found && $1 == "minos" { print $2; exit }')
	test "$minos" = 15.0 || {
		echo "error: $executable targets macOS $minos, expected 15.0" >&2
		echo failed >>"$status_file"
	}
	if strings "$executable" | grep -E '/(nix/store|opt/homebrew|private/var/folders|Users/runner/work)/' >/dev/null
	then
		echo "error: build-machine path embedded in $executable" >&2
		echo failed >>"$status_file"
	fi
	otool -L "$executable" | tail -n +2 | awk '{ print $1 }' | while IFS= read -r library
	do
		case "$library" in
			/System/Library/*|/usr/lib/*) ;;
			*) echo "error: non-system dependency in $executable: $library" >&2; echo failed >>"$status_file" ;;
		esac
	done
	codesign --verify --verbose "$executable" || echo failed >>"$status_file"
done
test ! -s "$status_file"

echo 'Darwin archive validation passed.'
