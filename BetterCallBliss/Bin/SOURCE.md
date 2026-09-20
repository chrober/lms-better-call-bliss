# Binary provenance

The deployable `bliss-playlist-optimizer` executables are intentionally not
committed to this repository. Plugin packages fetch platform artifacts from the
separate `chrober/bliss-playlist-optimizer` repository.

Latest packaged optimizer source:

- Optimizer release: `v0.2.0`
- Optimizer commit: `27a3395d1b4870d4c02c4a956cb63b0c33ce0b08`
- Program contract: `0.2.0`, core API `0.1`, guidance SPI `2`
- Last.fm guidance release: `v0.1.0`
- Last.fm guidance commit: `20c2782380f9f98de8c18aef2b44c2f467f90ac5`
- Play-count guidance release: `v0.1.0`
- Play-count guidance commit: `882ef9498114b2d6161d3e5bc84901d785636099`

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
