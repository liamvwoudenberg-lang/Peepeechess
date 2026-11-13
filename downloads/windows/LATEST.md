# Windows exe: where to get the latest build

The exe is now too big for a file in the repository (the paladin character models make the zip about 200 MB; GitHub refuses
files over 100 MB), so it is built on GitHub instead:

1. Every push that changes the game builds it automatically: **Actions > "Latest Windows exe" > the newest run > Artifacts >
   `Peepeechess-windows-x86_64`** (a zip with `Peepeechess.exe`; kept 30 days; you need to be signed in to GitHub).
2. On `main` the same workflow also refreshes the pre-release **"latest-windows"** on the Releases page (public download).
3. To build it yourself on Linux (or WSL): `bash tools/package/build_release_local.sh <tag>`; the exe lands in
   `artifacts/release/Peepeechess-windows-x86_64.exe` (see `docs/application/EXPORTS.md`).

The exe is unsigned (SmartScreen: *More info* > *Run anyway*) and has never been run on a real Windows PC by the developers.
