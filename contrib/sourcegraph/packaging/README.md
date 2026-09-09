# Sourcegraph Git archives

These scripts produce full, relocatable Git installations for Sourcegraph
engineer Macs and Amp orbs. They do not change Git behavior. Both builders
export the exact upstream-compatible `v2.55.0` source at commit
`e9019fcafe0040228b8631c30f97ae1adb61bcdc`, regardless of the branch from
which the packaging script runs.

The next immutable downstream release is `sourcegraph/v2.55.0-3`, whose Git
binary reports `2.55.0.sourcegraph.3`. It follows the stock-zlib
`sourcegraph/v2.55.0-2` release and consists of exactly these files:

* `git-sourcegraph-v2.55.0-3-linux-amd64.tar.gz`
* `git-sourcegraph-v2.55.0-3-linux-amd64.tar.gz.sha256`
* `git-sourcegraph-v2.55.0-3-darwin-arm64.tar.gz`
* `git-sourcegraph-v2.55.0-3-darwin-arm64.tar.gz.sha256`

Existing downstream tags and assets remain immutable.

Each archive has one `git-sourcegraph/` root. Stripping that directory exposes
`bin/`, `libexec/`, `share/`, optional `lib/`, and `BUILD-INFO`. The latter
records the source tag and commit, downstream version, build host, dependency
versions, recipe commit, and the identity embedded in Git. The source commit is
what was compiled; the recipe commit identifies the packaging implementation.
Consumers should verify the checksum sidecar before extracting.

`release.sh` is the source of truth for upstream version, release revision, Git
version, and source identity. It currently pins upstream `v2.55.0` because this
experiment has no behavior patches. When a future Sourcegraph behavior patch
lands, update the source ref and commit to the exact downstream revision
containing that patch; never leave the builder exporting an older upstream
commit.

## Linux AMD64

Install Docker, then run:

```console
./contrib/sourcegraph/packaging/build-linux.sh
./contrib/sourcegraph/packaging/validate-linux-archive.sh \
  artifacts/git-sourcegraph-v2.55.0-3-linux-amd64.tar.gz
```

The builder image starts from Debian 12 at a pinned multi-platform image
digest. `BUILD-INFO` captures the selected amd64 image's installed package
versions. The archive bundles the non-glibc dynamic dependency closure and
uses relative ELF RPATHs; glibc itself remains at Debian 12's 2.36 baseline.
Git links a checksum-pinned zlib-ng 2.3.3 static library built with its native
API, allowing its optimized implementation to coexist with ordinary zlib used
by other dependencies without adding a runtime library requirement.
Installed executables are stripped without removing features.
Git's Rust components remain enabled and are built with Debian's Rust toolchain.
The build container uses the invoking user's numeric UID and GID so bind-mount
contents and resulting artifacts remain owned and removable by that user.
The validator moves the unpacked tree, checks source identity, templates,
PCRE2, user config, `/etc/gitconfig`, HTTPS, and all ELF dependencies.

## macOS ARM64

The Mac artifact supports the latest released macOS major (26) and the
previous major (15) on Apple Silicon. Build and validate it on either supported
major. Install Xcode command-line tools, Rust, and GNU tar, then run:

```console
xcode-select --install # if the tools are not already installed
brew install rust gnu-tar
./contrib/sourcegraph/packaging/build-darwin.sh
./contrib/sourcegraph/packaging/validate-darwin-archive.sh \
  artifacts/git-sourcegraph-v2.55.0-3-darwin-arm64.tar.gz
```

The `Darwin ARM64 archive` job runs the same commands on GitHub's macOS 15
ARM64 runner and uploads the archive and checksum as a temporary workflow
artifact. It does not create tags, releases, or release assets.

The script discards inherited Nix SDK, compiler, and library search settings;
uses an Apple Xcode SDK; and currently targets macOS 15 by default. If
`xcode-select` points outside the normal Apple developer directories, the
script uses `/Applications/Xcode.app` when available and otherwise stops before building.
Override Xcode with `SOURCEGRAPH_GIT_DEVELOPER_DIR` or the deployment floor with
`SOURCEGRAPH_GIT_DEPLOYMENT_TARGET` only when deliberately preparing a
different artifact. It downloads checksum-pinned PCRE2 10.48 source and builds
it statically for the same target. Git uses the macOS SDK's curl, iconv, and
system libraries. Localization is disabled because macOS has no system libintl
and linking an incidental Homebrew gettext would make the archive depend on
the build machine. Git still includes its English fallthrough messages.
The builder also downloads and statically links the same checksum-pinned
zlib-ng 2.3.3 native library used by the Linux archive.

The full install includes `git-credential-osxkeychain`, rejects non-system
Mach-O dependencies (including `/opt/homebrew` and build paths), verifies
arm64 and the configured deployment floor, strips ephemeral source/staging paths,
and then ad-hoc signs unsigned installed binaries. Ad-hoc signatures are not
Apple notarization and do not establish publisher identity.

Before release, unpack the archive into two different
directories and run `bin/git version --build-options`, `bin/git init`, a PCRE2
`git grep -P`, an HTTPS clone/fetch, and the team's normal SSH, GPG signing, and
Git LFS workflows. Inspect every Mach-O file with `otool -L` and
`codesign --verify --verbose`. Publish the checksummed archives under an
immutable downstream tag; sign that tag separately when signing infrastructure
is available. Creating the tag or GitHub release is intentionally outside
these scripts.

Sourcegraph gitserver clears `credential.helper`, so an interactive
`credential-osxkeychain` round trip is not a service-release gate. The helper
remains included for other uses; validate it separately before broad engineer
adoption. A deployment target below the two supported majors is conservative
binary metadata, not a promise of runtime support for that older macOS release.

## License notices

Both archives include Git's `COPYING` and zlib-ng's `LICENSE.md` under
`LICENSES/`. Darwin also includes the pinned PCRE2 source's `LICENCE`. Linux
includes Debian's copyright notice for every package whose shared library is
copied into `lib/`, while
`BUNDLED-LIBRARIES` records each library's exact binary and source package
versions and a Debian source-retrieval link. References to Debian's
`/usr/share/common-licenses` resolve within `LICENSES/debian/common-licenses`.
System libraries referenced by the Darwin archive are not redistributed.
Release notes should link the exact Git, PCRE2, and zlib-ng sources; checksum
sidecars are checksums, not signatures.
