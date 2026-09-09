#!/bin/sh
set -eu

archive=${1:?usage: validate-linux-archive.sh ARCHIVE}
expected_commit=e9019fcafe0040228b8631c30f97ae1adb61bcdc
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

roots=$(tar -tzf "$archive" | sed 's,/.*,,' | LC_ALL=C sort -u)
test "$roots" = git-sourcegraph

for location in first/a second/moved/prefix
do
	mkdir -p "$work/$location"
	tar -xzf "$archive" -C "$work/$location" --strip-components=1
	git="$work/$location/bin/git"
	test -s "$work/$location/LICENSES/Git-COPYING"
	test -s "$work/$location/BUNDLED-LIBRARIES"
	test "$($git --version)" = 'git version 2.55.0'
	$git version --build-options | grep -F "built from commit: $expected_commit"
	test "$($git --exec-path)" = "$work/$location/libexec/git-core"
	test "$($git --html-path)" = "$work/$location/share/doc/git-doc"

	home="$work/home"
	mkdir -p "$home"
	HOME="$home" "$git" config --global sourcegraph.archive-test true
	test "$(HOME="$home" "$git" config --global --get sourcegraph.archive-test)" = true
	GIT_CONFIG_SYSTEM=/dev/null HOME="$home" "$git" init -q "$work/repository"
	test -f "$work/repository/.git/hooks/applypatch-msg.sample"
	printf 'needle\n' >"$work/repository/content"
	GIT_CONFIG_SYSTEM=/dev/null HOME="$home" "$git" -C "$work/repository" add content
	GIT_CONFIG_SYSTEM=/dev/null HOME="$home" "$git" -C "$work/repository" grep -P 'n(?=eedle)'
	rm -rf "$work/repository"
done

# Every bundled shared library identifies its exact Debian binary/source
# package, source retrieval location, and included copyright notice.
prefix="$work/second/moved/prefix"
test -s "$prefix/LICENSES/debian/README"
test -s "$prefix/LICENSES/debian/common-licenses/GPL-2"
test -s "$prefix/LICENSES/debian/common-licenses/LGPL-2.1"
tab=$(printf '\t')
tail -n +2 "$prefix/BUNDLED-LIBRARIES" | while IFS="$tab" read -r \
	library binary_package binary_version source_package source_version source_url copyright_notice
do
	test -n "$binary_package" && test -n "$binary_version"
	test -n "$source_package" && test -n "$source_version"
	test "$source_url" = "https://snapshot.debian.org/package/$source_package/"
	test -s "$prefix/$copyright_notice"
	test -f "$prefix/lib/$library"
done
for library in "$prefix"/lib/*
do
	awk -F '\t' -v library="$(basename "$library")" \
		'NR > 1 && $1 == library { found = 1 } END { exit !found }' \
		"$prefix/BUNDLED-LIBRARIES"
done

# Exercise HTTPS with the packaged curl/SSL dependency closure.
GIT_CONFIG_SYSTEM=/dev/null HOME="$work/home" \
	"$work/second/moved/prefix/bin/git" ls-remote \
	https://github.com/git/git.git HEAD | grep -E '^[0-9a-f]{40}[[:space:]]+HEAD$'

# The default remains host /etc/gitconfig; user config and external tools such
# as ssh, gpg, and git-lfs are deliberately discovered from the host PATH.
strings "$work/second/moved/prefix/bin/git" | grep -Fx /etc/gitconfig
test ! -e "$work/second/moved/prefix/etc/gitconfig"
if test -s /etc/gitconfig
then
	"$work/second/moved/prefix/bin/git" config --system --show-origin --list |
		awk -F '\t' '$1 != "file:/etc/gitconfig" { exit 1 } END { if (NR == 0) exit 1 }'
fi
GIT_CONFIG_NOSYSTEM=1 HOME="$work/home" \
	"$work/second/moved/prefix/bin/git" config --get sourcegraph.archive-test | grep -Fx true
mkdir "$work/isolated-home"
! GIT_CONFIG_NOSYSTEM=1 HOME="$work/isolated-home" \
	"$work/second/moved/prefix/bin/git" config --get commit.gpgsign

# Dashed external integrations continue to resolve through PATH. This is the
# mechanism used by git-lfs; SSH and signing programs are likewise external.
mkdir "$work/external"
cat >"$work/external/git-lfs" <<EOF
#!/bin/sh
echo external-lfs-ok
EOF
chmod +x "$work/external/git-lfs"
PATH="$work/external:$PATH" "$work/second/moved/prefix/bin/git" lfs version | grep -Fx external-lfs-ok

find "$work/second/moved/prefix/bin" "$work/second/moved/prefix/libexec" \
	-type f -perm -111 -exec file {} + | sed -n 's/: .*ELF .*//p' |
while IFS= read -r executable
do
	if ldd "$executable" | grep -q 'not found'
	then
		ldd "$executable" >&2
		exit 1
	fi
	readelf -d "$executable" | grep -E 'RPATH|RUNPATH' | grep -F '$ORIGIN'
done

echo 'Linux archive validation passed.'
