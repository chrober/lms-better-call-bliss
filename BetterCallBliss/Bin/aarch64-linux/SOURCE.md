# Binary provenance

The deployable `bliss-playlist-optimizer` executable is intentionally not
committed to this repository. Plugin packages and development deployments
should fetch an ARM64 artifact from the separate
`chrober/bliss-playlist-optimizer` repository.

Latest deployed ARM64 artifact:

- Optimizer commit: `f231023b8baa25dc7cf11ff74a1747adb17e6337`
- Program contract: `0.1.0`, core API `0.1`
- SHA-256: `43f0ac5dc611413f4566bc37838c36a3dfafb372af626d03512f5c7e5dd40540`
- Workflow run: <https://github.com/chrober/bliss-playlist-optimizer/actions/runs/31252986801>

Packaging or deployment should download that artifact, place it at
`BetterCallBliss/Bin/aarch64-linux/bliss-playlist-optimizer` in the package or
target plugin directory, set it executable, and then run
`bliss-playlist-optimizer version --json` on the target LMS host. If a newer
artifact is used, update the commit, workflow run, and checksum above.
