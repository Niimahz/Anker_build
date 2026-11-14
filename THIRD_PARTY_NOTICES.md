# Third-party software notices

Anker uses open-source dependencies. The original Anker project license does **not** replace their licenses.

| Dependency | Upstream | License (verify exact vendored version) |
| --- | --- | --- |
| ZIPFoundation | https://github.com/weichsel/ZIPFoundation | MIT |
| libarchive-swift | https://github.com/kmworks/libarchive-swift | BSD-2-Clause (verify bundled notices) |
| libarchive | https://www.libarchive.org/ | BSD-style licenses and component notices |
| zstd.swift | https://github.com/awxkee/zstd.swift | CC0 1.0 (upstream LICENSE.md; reference in LICENSES/ZSTD_SWIFT_CC0_1.0.txt). Its bundled libzstd.xcframework requires a separate native-binary notice and provenance review. |

**Before distributing binaries:** retain and bundle the full upstream license and copyright texts for the exact versions shipped, including `COPYING.libarchive` and other required notices. This summary is not a replacement for the full notices.

Apple WebKit and platform frameworks are provided under Apple's platform terms.

## Release compliance status

The dependency list above is a preliminary inventory, **not a completed binary redistribution notice bundle**. Before publicly distributing a new IPA, verify the resolved dependency revisions, include the full applicable copyright and license texts, and check any bundled C libraries and transitive dependencies. A public GitHub repository does not by itself grant permission to redistribute third-party game art or games.

The original Anker source code is published under the repository's MIT LICENSE. This license does not supersede third-party licenses, copyright notices, or trademark rights. The third-party binary redistribution review remains incomplete.

## Confirmed binary dependency packaging risks

The inspected upstream `awxkee/zstd.swift/Package.swift` uses a prebuilt `Sources/libzstd/libzstd.xcframework`. The inspected `kmworks/libarchive-swift/Package.swift` uses a downloaded `CArchive.xcframework.zip` binary target. Their wrapper licenses alone do **not** verify the provenance, exact embedded native library versions, or all required native copyright notices. Verify these before public IPA distribution.

The project's `project.yml` currently references `zstd.swift` on mutable `master`; a reviewed immutable commit is required for reproducible public release builds.
