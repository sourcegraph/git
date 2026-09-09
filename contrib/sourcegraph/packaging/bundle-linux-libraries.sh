#!/bin/sh
set -eu

prefix=${1:?usage: bundle-linux-libraries.sh PREFIX}
mkdir -p "$prefix/lib"
notices="$prefix/LICENSES/debian"
mkdir -p "$notices"
cp -R /usr/share/common-licenses "$notices/common-licenses"
cat >"$notices/README" <<'EOF'
Debian copyright notices in this directory may refer to license texts under
/usr/share/common-licenses. Their archived copies are in common-licenses/.
EOF
manifest="$prefix/BUNDLED-LIBRARIES"
printf 'library\tbinary_package\tbinary_version\tsource_package\tsource_version\tsource_retrieval\tcopyright_notice\n' >"$manifest"

find_elfs() {
	find "$prefix/bin" "$prefix/libexec" -type f -perm -111 -exec file {} + |
		sed -n 's/: .*ELF .*//p'
}

find_owning_package() {
	library=$1
	canonical=$(readlink -f "$library")
	for candidate in "$library" "$canonical"
	do
		case "$candidate" in
			/lib/*) alternate=/usr$candidate ;;
			/usr/lib/*) alternate=${candidate#/usr} ;;
			*) alternate= ;;
		esac
		for path in "$candidate" "$alternate"
		do
			test -n "$path" || continue
			if ownership=$(dpkg-query -S "$path" 2>/dev/null)
			then
				printf '%s\n' "$ownership" | sed -n '1{s/: \/.*//;p;}'
				return 0
			fi
		done
	done
	return 1
}

# ldd reports the complete transitive closure. Keep glibc, its loader, and the
# base POSIX libraries on the host so the archive retains Debian 12's glibc
# floor; bundle feature libraries such as curl, OpenSSL, PCRE2, and expat.
find_elfs | while IFS= read -r executable
do
	ldd "$executable"
done | awk '/=> \// { print $3 } /^\// { print $1 }' | LC_ALL=C sort -u |
while IFS= read -r library
do
	case "$(basename "$library")" in
		ld-linux-*|libc.so.*|libdl.so.*|libm.so.*|libpthread.so.*|libresolv.so.*|librt.so.*|libutil.so.*)
			continue ;;
	esac
	library_name=$(basename "$library")
	cp -L "$library" "$prefix/lib/$library_name"

	if package_spec=$(find_owning_package "$library")
	then
		:
	else
		echo "error: no Debian package owns $library" >&2
		exit 1
	fi
	package=${package_spec%%:*}
	package_metadata=$(dpkg-query -W \
		-f='${binary:Package}\t${Version}\t${source:Package}\t${source:Version}' \
		"$package_spec")
	tab=$(printf '\t')
	IFS="$tab" read -r binary_package binary_version source_package source_version <<EOF
$package_metadata
EOF
	copyright_source="/usr/share/doc/$package/copyright"
	test -f "$copyright_source" || {
		echo "error: missing Debian copyright notice for $package" >&2
		exit 1
	}
	copyright_name="$package.copyright"
	cp -L "$copyright_source" "$notices/$copyright_name"
	printf '%s\t%s\t%s\t%s\t%s\thttps://snapshot.debian.org/package/%s/\tLICENSES/debian/%s\n' \
		"$library_name" "$binary_package" "$binary_version" \
		"$source_package" "$source_version" "$source_package" \
		"$copyright_name" >>"$manifest"
done

for library in "$prefix"/lib/*
do
	patchelf --set-rpath '$ORIGIN' "$library"
done

find_elfs | while IFS= read -r executable
do
	relative=${executable#"$prefix"/}
	case "$relative" in
		bin/*) rpath='$ORIGIN/../lib' ;;
		libexec/git-core/*) rpath='$ORIGIN/../../lib' ;;
		*) echo "error: unknown executable location: $relative" >&2; exit 1 ;;
	esac
	patchelf --set-rpath "$rpath" "$executable"
done
