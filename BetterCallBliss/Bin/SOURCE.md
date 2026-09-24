# Binary provenance

The deployable `bliss-playlist-optimizer` executables are intentionally not
committed to this repository. Plugin packages fetch platform artifacts from the
separate `chrober/bliss-playlist-optimizer` repository.

Latest packaged optimizer source:

- Optimizer release: `v0.2.2`
- Optimizer commit: `5bc528c5f2b382e0210934dfcaa84a00676df5a7`
- Program contract: `0.2.2`, core API `0.1`, guidance SPI `2`
- Last.fm guidance release: `v0.1.1`
- Last.fm guidance commit: `1895172a3065f4f1e8ee23655f7e2357c7b32561`
- Play-count guidance release: `v0.1.1`
- Play-count guidance commit: `08f371774236651f8aa2252e99d7081bfac6ba22`

The GitHub release workflow downloads the optimizer and both guidance-provider
releases above, verifies each published `.sha256` file, places the binaries below the matching
`BetterCallBliss/Bin/<platform>/` folders in the release workspace, and creates
separate Linux, macOS, and Windows archives. The Linux archive contains the
x86_64, AArch64, and ARMHF binaries; macOS and Windows each contain only their
matching binary. Each target-specific package checksum is recorded separately
in the LMS plugin repository feed.

Supported package folders:

- `aarch64-linux/bliss-playlist-optimizer`
- `armhf-linux/bliss-playlist-optimizer`
- `x86_64-linux/bliss-playlist-optimizer`
- `mac/bliss-playlist-optimizer`
- `windows/bliss-playlist-optimizer.exe`

Each matching platform folder also contains:

- `bliss-guidance-lastfm` (`bliss-guidance-lastfm.exe` on Windows)
- `bliss-guidance-playcounts` (`bliss-guidance-playcounts.exe` on Windows)

If a newer native release is used, update its release tag and commit above.
The native release workflows own their build and test gates; the plugin release
workflow consumes only successful published artifacts.
