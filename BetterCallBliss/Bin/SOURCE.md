# Binary provenance

The deployable `bliss-playlist-optimizer` executables are intentionally not
committed to this repository. Plugin packages and development deployments build
or fetch platform artifacts from the separate `chrober/bliss-playlist-optimizer`
repository.

Latest packaged optimizer source:

- Optimizer commit: `f231023b8baa25dc7cf11ff74a1747adb17e6337`
- Program contract: `0.1.0`, core API `0.1`
- Previous ARM64 SHA-256: `43f0ac5dc611413f4566bc37838c36a3dfafb372af626d03512f5c7e5dd40540`
- Previous ARM64 workflow run: <https://github.com/chrober/bliss-playlist-optimizer/actions/runs/31252986801>

The GitHub release workflow checks out the optimizer source commit above,
builds the supported native targets, places the results below the matching
`BetterCallBliss/Bin/<platform>/` folders in the release package, and records
the package checksum in the LMS plugin repository feed.

Supported package folders:

- `aarch64-linux/bliss-playlist-optimizer`
- `armhf-linux/bliss-playlist-optimizer`
- `x86_64-linux/bliss-playlist-optimizer`
- `mac/bliss-playlist-optimizer`
- `windows/bliss-playlist-optimizer.exe`

If a newer optimizer commit is used, update the commit above and verify
`bliss-playlist-optimizer version --json` on each target family that is meant to
be advertised through the LMS repository feed.
