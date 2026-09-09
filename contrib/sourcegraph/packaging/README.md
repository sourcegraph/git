# Sourcegraph Git archives

These scripts produce full, relocatable Git installations for Sourcegraph
engineer Macs and Amp orbs. They do not change Git behavior. Both builders
export the exact upstream-compatible `v2.55.0` source at commit
`e9019fcafe0040228b8631c30f97ae1adb61bcdc`, regardless of the branch from
which the packaging script runs.

The intended immutable downstream release is `sourcegraph/v2.55.0-1`. A
release consists of exactly these files:

* `git-sourcegraph-v2.55.0-1-linux-amd64.tar.gz`
* `git-sourcegraph-v2.55.0-1-linux-amd64.tar.gz.sha256`
* `git-sourcegraph-v2.55.0-1-darwin-arm64.tar.gz`
* `git-sourcegraph-v2.55.0-1-darwin-arm64.tar.gz.sha256`

Each archive has one `git-sourcegraph/` root. Stripping that directory exposes
`bin/`, `libexec/`, `share/`, optional `lib/`, and `BUILD-INFO`. The latter
records the source tag and commit, downstream version, build host, dependency
versions, recipe commit, and the identity embedded in Git. The source commit is
what was compiled; the recipe commit identifies the packaging implementation.
Consumers should verify the checksum sidecar before extracting.

The source constants in both entry-point scripts move together. They currently
pin upstream `v2.55.0` because this experiment has no behavior patches. When a
future Sourcegraph behavior patch lands, update the source ref and commit to the
exact downstream revision containing that patch; never leave the builder
exporting an older upstream commit.

## Linux AMD64

Install Docker, then run:

```console
./contrib/sourcegraph/packaging/build-linux.sh
./contrib/sourcegraph/packaging/validate-linux-archive.sh \
  artifacts/git-sourcegraph-v2.55.0-1-linux-amd64.tar.gz
```

The builder image starts from Debian 12 at a pinned multi-platform image
digest. `BUILD-INFO` captures the selected amd64 image's installed package
versions. The archive bundles the non-glibc dynamic dependency closure and
uses relative ELF RPATHs; glibc itself remains at Debian 12's 2.36 baseline.
Installed executables are stripped without removing features.
Git's Rust components remain enabled and are built with Debian's Rust toolchain.
The build container uses the invoking user's numeric UID and GID so bind-mount
contents and resulting artifacts remain owned and removable by that user.
The validator moves the unpacked tree, checks source identity, templates,
PCRE2, user config, `/etc/gitconfig`, HTTPS, and all ELF dependencies.

## macOS ARM64

The Mac artifact must be built and validated on a supported Apple Silicon Mac.
Install Xcode command-line tools, Rust, and GNU tar, then run:

```console
xcode-select --install # if the tools are not already installed
brew install rust gnu-tar
./contrib/sourcegraph/packaging/build-darwin.sh
```

The script discards inherited Nix SDK, compiler, and library search settings;
uses an Apple Xcode SDK; and targets macOS 14 by default. If `xcode-select`
points outside the normal Apple developer directories, the script uses
`/Applications/Xcode.app` when available and otherwise stops before building.
Override Xcode with `SOURCEGRAPH_GIT_DEVELOPER_DIR` or the deployment floor with
`SOURCEGRAPH_GIT_DEPLOYMENT_TARGET` only when deliberately preparing a
different artifact. It downloads checksum-pinned PCRE2 10.48 source and builds
it statically for the same target. Git uses the macOS SDK's curl, iconv, and
system libraries. Localization is disabled because macOS has no system libintl
and linking an incidental Homebrew gettext would make the archive depend on
the build machine. Git still includes its English fallthrough messages.

The full install includes `git-credential-osxkeychain`, rejects non-system
Mach-O dependencies (including `/opt/homebrew` and build paths), verifies
arm64 and the macOS 14 deployment floor, strips ephemeral source/staging paths,
and then ad-hoc signs unsigned installed binaries. Ad-hoc signatures are not
Apple notarization and do not establish publisher identity.

Before an experimental service release, unpack the archive into two different
directories and run `bin/git version --build-options`, `bin/git init`, a PCRE2
`git grep -P`, an HTTPS clone/fetch, and the team's normal SSH, GPG signing, and
Git LFS workflows. Inspect every Mach-O file with `otool -L` and
`codesign --verify --verbose`. Publish the checksummed archives only as an
opt-in prerelease under an immutable downstream tag; sign that tag separately
when signing infrastructure is available. Creating the tag or GitHub release
is intentionally outside these scripts.

Validation on macOS 26.6.2 exercised those core workflows, but the locked
noninteractive login keychain prevented a `credential-osxkeychain` store/get/
erase round trip. The macOS 14 deployment floor was inspected in Mach-O load
commands, not run on macOS 14. Complete both checks before describing this as a
fully supported everyday Git replacement.

## License notices

Both archives include Git's `COPYING` under `LICENSES/`. Darwin also includes
the pinned PCRE2 source's `LICENCE`. Linux includes Debian's copyright notice
for every package whose shared library is copied into `lib/`, while
`BUNDLED-LIBRARIES` records each library's exact binary and source package
versions and a Debian source-retrieval link. References to Debian's
`/usr/share/common-licenses` resolve within `LICENSES/debian/common-licenses`.
System libraries referenced by the Darwin archive are not redistributed.
Release notes should link the exact Git and PCRE2 sources; checksum sidecars
are checksums, not signatures.
