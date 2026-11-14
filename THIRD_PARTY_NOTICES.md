# Third-party software notices

Anker uses open-source dependencies. The original Anker project license does **not** replace their licenses.

| Dependency | Upstream | License (verify exact vendored version) |
| --- | --- | --- |
| ZIPFoundation | https://github.com/weichsel/ZIPFoundation | MIT |
| libarchive-swift | https://github.com/kmworks/libarchive-swift | BSD-2-Clause (verify bundled notices) |
| libarchive | https://www.libarchive.org/ | BSD-style licenses and component notices |
| zstd.swift | https://github.com/awxkee/zstd.swift | Check exact checkout and transitive dependencies |

**Before distributing binaries:** retain and bundle the full upstream license and copyright texts for the exact versions shipped, including `COPYING.libarchive` and other required notices. This summary is not a replacement for the full notices.

Apple WebKit and platform frameworks are provided under Apple's platform terms.

## Release compliance status

The dependency list above is a preliminary inventory, **not a completed binary redistribution notice bundle**. Before publicly distributing a new IPA, verify the resolved dependency revisions, include the full applicable copyright and license texts, and check any bundled C libraries and transitive dependencies. A public GitHub repository does not by itself grant permission to redistribute third-party game art or games.

The project LICENSE currently reserves rights to the original Anker code; publishing source on GitHub does not automatically make it open source. Do not describe Anker as MIT-licensed unless the rights holder deliberately adopts that license.
