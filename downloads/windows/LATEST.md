# Windows exe: where to get the latest build

The exe is now too big for a file in the repository (the paladin character models make the zip about 200 MB; GitHub refuses
files over 100 MB), so it is built on GitHub instead:

1. Every push that changes the game builds it automatically: **Actions > "Latest Windows exe" > the newest run > Artifacts >
   `Peepeechess-windows-x86_64`** (a zip with `Peepeechess.exe`; kept 30 days; you need to be signed in to GitHub).
2. On `main` the same workflow also refreshes the pre-release **"latest-windows"** on the Releases page (public download).
3. To build it yourself on Linux (or WSL): `bash tools/package/build_release_local.sh <tag>`; the exe lands in
   `artifacts/release/release/Peepeechess-windows-x86_64.exe` (see `docs/application/EXPORTS.md`).

The exe is unsigned (SmartScreen: *More info* > *Run anyway*) and has never been run on a real Windows PC by the developers.

## Implementation audit test build — 2026-11-15

[Download the Windows zip](https://github.com/liamvwoudenberg-lang/Peepeechess/releases/download/audit-2026-11-15-a8c6ea4/Peepeechess-a8c6ea4-win64.zip)
or use the [prerelease page](https://github.com/liamvwoudenberg-lang/Peepeechess/releases/tag/audit-2026-11-15-a8c6ea4).
Built from `a8c6ea4440fb1d48154dd8c93e5d46d7cef9befe`, containing the 3D
colour-blind-highlight and computer-clock fixes. Later audit changes concern
validation and documentation. This feature-branch test build does not replace
the rolling `main` release.

[Release workflow](https://github.com/liamvwoudenberg-lang/Peepeechess/actions/runs/43658895149):
Linux package smoke, static Windows PE/PCK checks, headless Windows runner smoke
and publication succeeded. Physical Windows PC / Android device testing remains
open. No executable was committed to the repository.

SHA-256 (also available in the release's `SHA256SUMS.txt`):

```text
866d12f43c834128486208103bfeffa4dd234e9fbdf401e7749dea7a1ea4e9e1  Peepeechess-a8c6ea4-win64.zip
bc0ab16a1d801155e525618f3444cb25c145cb576d9421f951c8a2330a61c5b5  Peepeechess-windows-x86_64.exe
```
