# Playlist Breaking Bad? Better Call Bliss.

<p align="center">
  <img src="docs/images/better-call-bliss-banner.png" alt="Playlist Breaking Bad? Better Call Bliss." width="900">
</p>

**Better Call Bliss** is a Lyrion Music Server plugin that turns a saved
playlist into a smoother listening journey. It can reorder the existing songs,
insert suitable bridge tracks, preserve the original order while filling its
gaps, or grow a short seed playlist into a longer mix. Every job is previewed
before a new playlist is written, and artist, album, and track repeat rules
remain hard constraints.

The plugin owns the Lyrion user interface, settings, Last.fm integration,
background jobs, result review, and playlist creation. CPU-intensive acoustic
scoring and route search are delegated to the network-free Rust engine
[bliss-playlist-optimizer](https://github.com/chrober/bliss-playlist-optimizer),
which is bundled with supported plugin packages.

## What it does

- Reorders every song in a curated playlist for better transition flow.
- Adds bridges automatically only where a transition is difficult.
- Adds exactly a requested number of tracks or grows seeds to a target size.
- Preserves the existing order when requested and inserts tracks only in gaps.
- Uses dynamic Adaptive Bliss similarity, optional learned preferences,
  per-job variation, and optional Last.fm similar-artist guidance.
- Shows a read-only preview and diagnostics before creating a verified copy.
- Never modifies bliss.db, the source audio files, or the source playlist.

See [Playlist optimization modes and options](ALGORITHMS.md) for reader-friendly
explanations, technical flowcharts, option ranges, and the exact boundary
between working and planned modes. See [UX status](docs/UX_STATUS.md) for the
complete feature matrix.

## Requirements

- Lyrion Music Server 8.5 or newer.
- A compatible
  [lms-blissmixer](https://github.com/chrober/lms-blissmixer) installation,
  currently the fork paired with this project. Better Call Bliss deliberately
  reuses its analyzed library, shared scoring behavior, and configured defaults
  without modifying the plugin. Training a learned matrix is optional for
  BlissMixer itself.
- A completed Bliss analysis that produced a readable bliss.db in the Lyrion
  preferences directory.
- A readable learned_matrix.json is optional. When present, Adaptive can blend it
  with dynamic variance. When absent, Better Call Bliss follows the BlissMixer
  fallback shape: multi-track contexts use variance and one-track contexts use
  the configured Static BlissMixer weights. See
  [Is a learned matrix optional?](ALGORITHMS.md#is-a-learned-matrix-optional).
- A configured local Lyrion music folder whose tracks correspond to bliss.db.
- A bliss-playlist-optimizer binary for the server platform. Release packages
  bundle native binaries for Windows, macOS, x86_64 Linux, ARM64 Linux, and
  ARMHF Linux.

[LastMix](https://github.com/AF-1/lms-lastmix) is optional. When installed and
enabled, it supplies anonymous Last.fm similar-track and similar-artist evidence. Missing
Internet access, provider failures, and rate limits fall back to local Bliss
scoring and do not fail the optimization job.

## Basic use

1. Open **Extras > Better Call Bliss**.
2. Select a saved playlist.
3. Choose the source-order policy, addition mode, and per-job options.
4. Run the read-only Preview.
5. Review the proposed order, additions, proofs, and diagnostics.
6. Create an optimized copy when satisfied.

The source playlist is preserved. Source overwrite and all other unfinished
features are visibly marked as unavailable.

## Release and publishing workflow

GitHub Actions workflow `.github/workflows/release.yml` builds a release package
without committing native binaries to this repository:

1. Checks out `chrober/bliss-playlist-optimizer` at the commit documented in
   `BetterCallBliss/Bin/SOURCE.md`, unless an `optimizer_ref` override is
   supplied manually.
2. Builds optimizer binaries for `x86_64-linux`, `aarch64-linux`,
   `armhf-linux`, `mac`, and `windows`.
3. Copies those binaries into the matching `BetterCallBliss/Bin/<platform>/`
   folders only inside the release workspace.
4. Creates `lms-better-call-bliss-<version>.zip` plus SHA-1 and SHA-256 files.
5. Publishes the GitHub Release and, unless disabled, updates
   `chrober/lms-plugins` `repo.xml` with immutable release-asset URLs for
   `unix`, `mac`, and `windows`.

The cross-repository feed update requires a repository secret named
`LMS_PLUGINS_TOKEN` with contents-write access to `chrober/lms-plugins`. Use
`dry_run=true` to build and inspect the package as a workflow artifact without
creating a release or touching the plugin feed.

## Repository contents

- `BetterCallBliss/` is the installable Lyrion plugin source tree. It contains
  the Perl plugin modules, classic-web templates, settings page, strings,
  icons, and `install.xml` metadata.
- The platform-specific `bliss-playlist-optimizer` executables are
  intentionally not committed here. They are built from the separate
  [chrober/bliss-playlist-optimizer](https://github.com/chrober/bliss-playlist-optimizer)
  repository by GitHub Actions and copied into deployment/package artifacts.
  The expected optimizer source commit, supported package folders, and release
  packaging contract are documented in `BetterCallBliss/Bin/SOURCE.md`.
  `.gitignore` prevents local executables from being accidentally committed.
- `tests/` contains lightweight Perl regression tests for the plugin glue code.
  The tests stub the relevant LMS/LastMix APIs and check request JSON typing
  plus Last.fm evidence handling. This folder is not installed as runtime
  plugin UI; it is committed so future changes can catch these integration
  regressions.
- `docs/`, `ALGORITHMS.md`, and `README.md` are project documentation and are
  not required for the plugin to run.

## Component boundary

~~~mermaid
flowchart LR
    LMS["Lyrion saved playlist"] --> P["Better Call Bliss plugin"]
    BM["lms-blissmixer settings<br/>bliss.db and optional<br/>learned matrix"] --> P
    LM["Optional LastMix<br/>Last.fm track and artist evidence"] --> P
    P --> O["bliss-playlist-optimizer"]
    O --> C["bliss-mixer-core<br/>shared Bliss scoring"]
    O --> P
    P --> V["Read-only preview"]
    V -->|"user accepts"| N["Verified new Lyrion playlist"]
~~~

Better Call Bliss is under active development. The current implementation
supports Adaptive scoring, optimized or preserved source order, reorder-only,
automatic additions, exact-count additions, and seed growth. Disabled controls
in the UI describe planned capabilities rather than silently pretending to
work.

Licensed under GPL-3.0-only. See [LICENSE](LICENSE).
