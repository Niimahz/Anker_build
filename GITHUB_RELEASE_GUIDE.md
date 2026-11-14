# Publishing an unsigned Anker IPA on GitHub Releases

The workflow [Prepare GitHub IPA Release](.github/workflows/prepare-github-release.yml) builds an **unsigned** IPA from the selected Git commit, verifies the app's version, build number and bundle ID, checks the ZIP container and produces a SHA-256 checksum.

## Prepare and inspect before publishing

1. Open [Actions](https://github.com/Niimahz/Anker_build/actions/workflows/prepare-github-release.yml).
2. Choose **Run workflow** on the intended branch; set version to `1.0.0`.
3. Leave **Publish a public GitHub prerelease** **unchecked** for the first run.
4. When the workflow succeeds, download `Anker-1.0.0-release-candidate` from **Artifacts**. It includes `Anker-1.0.0-unsigned.ipa`, `SHA256SUMS.txt` and `RELEASE_NOTES.md`.
5. Check the checksum: `shasum -a 256 -c SHA256SUMS.txt` from the folder containing the IPA.
6. Sign and install the IPA on a real iPhone. Complete the smoke tests in [RELEASE_1.0.0_RC.md](RELEASE_1.0.0_RC.md). **Do not distribute before these checks pass.**

## Publish after approval

Run the workflow again from the reviewed commit with **Publish a public GitHub prerelease** checked. It creates `v1.0.0-rc.1` with the unsigned IPA, checksum and notes. It will **refuse to overwrite** an existing release tag. The GitHub Actions workflow needs repository **Actions** enabled and permission to write release contents.

**Important:** The resulting GitHub Release is a public *prerelease*, not an App Store build. The unsigned IPA must be signed by each installer using a compatible signing method. GitHub does not sign the app.

For a future release version, update `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, release notes, and the workflow's version/build validation before publishing. The current workflow intentionally only verifies build 1 and release-candidate tag 1.
