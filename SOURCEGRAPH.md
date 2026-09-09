# Sourcegraph Git fork

`master` follows upstream Git. `sourcegraph` carries Sourcegraph changes as a
linear patch series based on an upstream stable release tag. Target downstream
pull requests there. The current experiment is based on upstream `v2.55.0`,
commit `e9019fcafe0040228b8631c30f97ae1adb61bcdc`, and contains no Git behavior
changes.

Keep each downstream change as a small, rebasable commit with no merge commits.
Develop topics from `sourcegraph` and squash them to one coherent commit when
merging. For each release, select or retain an upstream stable release tag,
rebase the downstream series onto it, review `git range-diff`, run tests, and
build the artifacts before tagging the tested downstream tip. Never base a
release on an arbitrary upstream `master` revision, tag the upstream commit, or
put downstream patches on `master`.

Release tags use `sourcegraph/v<upstream-version>-<revision>`, for example
`sourcegraph/v2.55.0-2`. The revision starts at 1, increments for behavior,
packaging, or rebuild releases on the same upstream baseline, and resets to 1
when the upstream version changes. Tags and assets are immutable. Release
metadata records the corresponding Git source and packaging recipe commits
separately. Future builds should report a downstream Git version such as
`2.55.0.sourcegraph.2`; the immutable first release reports plain `2.55.0` and
records its downstream identity in `BUILD-INFO`.

Distribution has three separate owners:

* `contrib/sourcegraph/packaging` manually builds complete relocatable macOS
  ARM64 and glibc Linux AMD64 archives.
* Sourcegraph's Wolfi configuration builds APKs for production images.
* The main Sourcegraph repository pins published archive URLs and checksums for
  engineer and Amp-orb installation through mise.

Archive publication and consumer pin activation are coordinated steps. Never
invent release URLs or checksums, and do not treat a packaging recipe commit as
the Git source commit unless that exact revision was compiled.
