# Anker Game Bridge (iOS)

A SwiftUI utility for preparing portable Windows game folders for manual import into Playport or Madeira. **It does not run Windows games.**

## Implemented in source
- Import game folders or archive files through iOS Files
- Direct HTTP(S) file download
- Embedded AnkerGames website browser (site downloads are **not** intercepted by the app)
- ZIP, 7z, RAR/RAR5 and TAR extraction using [kmworks/libarchive-swift](https://github.com/kmworks/libarchive-swift) with normalized permissions and built-in unsafe-path checks
- Scan extracted folders for .exe files
- Share prepared game folders

## Known limits
- Not yet compiled or tested on an iPhone. No successful unsigned IPA has been verified.
- Password-protected archives and multipart RAR/7z are **not** guaranteed to work.
- The bundled libarchive disables some optional compression filters (e.g. xz/lzma filter); 7z *container* decoding is enabled.
- Browser downloads are not wired into the app downloader.
- EXE selection is manual; Playport/Madeira compatibility is not guaranteed.
- Large archive extraction is synchronous and can block the UI. Ensure sufficient free disk space.

## Build
GitHub Actions → **Build unsigned IPA** → Run workflow. If it passes, download `AnkerGameBridge-unsigned-IPA` artifact. The IPA is unsigned; signing and device testing are separate steps.

## Third-party notices
The app links `kmworks/libarchive-swift` (BSD-2-Clause) and bundled upstream libarchive (BSD-style); binary redistributions must retain the package LICENSE and COPYING.libarchive notices. ZIPFoundation is MIT licensed.
