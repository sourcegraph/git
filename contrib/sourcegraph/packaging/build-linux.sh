#!/bin/sh
set -eu

SOURCE_TAG=v2.55.0
SOURCE_COMMIT=e9019fcafe0040228b8631c30f97ae1adb61bcdc
RELEASE_VERSION=v2.55.0-1
IMAGE=git-sourcegraph-linux-builder:v2.55.0-1

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
cleanup() {
	status=$?
	trap - EXIT HUP INT TERM
	rm -rf "$work" || :
	exit "$status"
}
trap cleanup EXIT HUP INT TERM

# Export the release source rather than building whichever fork branch happens
# to contain these packaging scripts.
git -C "$root" archive "$SOURCE_COMMIT" | tar -x -C "$work"
mkdir -p "$work/contrib/sourcegraph"
cp -R "$root/contrib/sourcegraph/packaging" "$work/contrib/sourcegraph/"

docker build -f "$root/contrib/sourcegraph/packaging/Dockerfile.linux" -t "$IMAGE" "$root"
docker run --rm \
	--user "$(id -u):$(id -g)" \
	-e HOME=/tmp \
	-e SOURCE_DATE_EPOCH="$(git -C "$root" show -s --format=%ct "$SOURCE_COMMIT")" \
	-e SOURCE_COMMIT="$SOURCE_COMMIT" \
	-e SOURCE_TAG="$SOURCE_TAG" \
	-e RECIPE_COMMIT="$RECIPE_COMMIT" \
	-e RELEASE_VERSION="$RELEASE_VERSION" \
	-v "$work:/src" \
	-v "$output:/out" \
	"$IMAGE"
