# Binary provenance

The deployable `bliss-playlist-optimizer` executables are intentionally not
committed to this repository. Plugin packages fetch platform artifacts from the
separate `chrober/bliss-playlist-optimizer` repository.

Latest packaged optimizer source:

- Optimizer release: `v0.1.6`
- Optimizer commit: `04763ad7b33c0b030f2edff5230351f5ce8f26e4`
- Program contract: `0.1.6`, core API `0.1`

The GitHub release workflow downloads the optimizer release above, verifies each
published `.sha256` file, places the binaries below the matching
`BetterCallBliss/Bin/<platform>/` folders in the release package, and records
the package checksum in the LMS plugin repository feed.

Supported package folders:

- `aarch64-linux/bliss-playlist-optimizer`
- `armhf-linux/bliss-playlist-optimizer`
- `x86_64-linux/bliss-playlist-optimizer`
- `mac/bliss-playlist-optimizer`
- `windows/bliss-playlist-optimizer.exe`

If a newer optimizer release is used, update the release tag and commit above.
The optimizer release workflow owns the native build and test gate; the plugin
release workflow consumes only successful published optimizer assets.
