# Sourcegraph Git fork

`master` follows upstream Git. `k/sourcegraph` carries Sourcegraph changes as a
linear patch series based on a deliberately selected upstream release or
revision. Target downstream pull requests there. The current experiment is
based on upstream `v2.55.0`, commit
`e9019fcafe0040228b8631c30f97ae1adb61bcdc`, and contains no Git behavior
changes.

Keep each downstream change as a small, rebasable commit with no merge commits.
Develop topics from `k/sourcegraph` and squash them to one coherent commit when
merging. To change the upstream baseline, coordinate the update, rebase the
series, and review `git range-diff` before force-pushing with an exact lease.
Leave `master` untouched by downstream patches.

Release tags are immutable and namespaced, for example
`sourcegraph/v2.55.0-1`. Release metadata must record both the exact Git source
commit and the recipe revision that produced an artifact. Packaging-only
commits do not change the current source identity. Future behavior patches must
be included in the source being built; do not bypass them with a hard-coded
older upstream commit when advancing the patch series.

Distribution has three separate owners:

* `contrib/sourcegraph/packaging` manually builds complete relocatable macOS
  ARM64 and glibc Linux AMD64 archives.
* Sourcegraph's Wolfi configuration builds APKs for production images.
* The main Sourcegraph repository pins published archive URLs and checksums for
  engineer and Amp-orb installation through mise.

Archive publication and consumer pin activation are coordinated steps. Never
invent release URLs or checksums, and do not treat a packaging recipe commit as
the Git source commit unless that exact revision was compiled.
