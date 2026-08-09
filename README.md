# Playlist Breaking Bad? Better Call Bliss.

<p align="center">
  <img src="docs/images/better-call-bliss-banner.png" alt="Playlist Breaking Bad? Better Call Bliss." width="900">
</p>

**Better Call Bliss** is a Lyrion Music Server plugin that turns a saved
playlist or a current player queue snapshot into a smoother listening journey.
It can reorder the existing songs, insert suitable bridge tracks, preserve the
original order while filling its gaps, grow a short seed playlist into a longer
mix, or rebuild the upcoming part of a live queue. Every job is previewed before
anything is saved or sent to a player, and artist, album, and track repeat rules
remain hard constraints.

The plugin owns the Lyrion user interface, settings, Last.fm integration,
background jobs, result review, playlist persistence, and player-queue output.
CPU-intensive acoustic
scoring and route search are delegated to the network-free Rust engine
[bliss-playlist-optimizer](https://github.com/chrober/bliss-playlist-optimizer),
which is bundled with supported plugin packages.

## What it does

- Reorders every song in a curated playlist or queue snapshot for better transition flow.
- Adds bridges automatically only where a transition is difficult.
- Adds exactly a requested number of tracks or grows seeds to a target size.
- Preserves the existing order when requested and inserts tracks only in gaps.
- Uses dynamic Adaptive Bliss similarity, optional learned preferences,
  per-job variation, and optional Last.fm similar-track and similar-artist guidance.
- Uses a saved playlist, a full player queue, only upcoming queue tracks, or the
  current-plus-upcoming queue segment as input.
- Shows a read-only preview and diagnostics before creating a verified copy,
  overwriting the source playlist, or sending the result to a player queue.
- Can replace, append to, play next, or replace only the upcoming part of a
  player queue, with optional start playback.
- Never modifies bliss.db or the source audio files.

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
2. Select either a saved playlist or a player queue snapshot as the source.
3. Choose the source-order policy, addition mode, and per-job options.
4. Run the read-only Preview.
5. Review the proposed order, additions, proofs, and diagnostics.
6. Accept the preview by creating a copy, overwriting the source playlist when
   available, or sending the result to a player queue.

When a live player is used as both source and target, **Replace upcoming tracks**
keeps the currently playing song untouched and updates only the queue tail. All
unsupported combinations are visibly marked or rejected before persistence.

## Release and publishing workflow

GitHub Actions workflow `.github/workflows/release.yml` builds a release package
without committing native binaries to this repository:

1. Reads the pinned `bliss-playlist-optimizer` release from
   `BetterCallBliss/Bin/SOURCE.md`, unless an `optimizer_release` override is
   supplied manually.
2. Downloads the published optimizer binaries for `x86_64-linux`,
   `aarch64-linux`, `armhf-linux`, `mac`, and `windows` from that release and
   verifies their `.sha256` files.
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
  intentionally not committed here. They are published by the separate
  [chrober/bliss-playlist-optimizer](https://github.com/chrober/bliss-playlist-optimizer)
  repository release workflow and copied into deployment/package artifacts by this plugin release workflow.
  The expected optimizer release, supported package folders, and release
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
    Q["Current player queue snapshot"] --> P
    BM["lms-blissmixer settings<br/>bliss.db and optional<br/>learned matrix"] --> P
    LM["Optional LastMix<br/>Last.fm track and artist evidence"] --> P
    P --> O["bliss-playlist-optimizer"]
    O --> C["bliss-mixer-core<br/>shared Bliss scoring"]
    O --> P
    P --> V["Read-only preview"]
    V -->|"user accepts"| N["Verified new Lyrion playlist"]
~~~

Better Call Bliss is under active development. The current implementation
supports Adaptive scoring, optimized or preserved source order, saved-playlist
and player-queue sources, playlist and queue outputs, reorder-only, automatic
additions, exact-count additions, target/double track-count presets, and seed
growth. Disabled controls
in the UI describe planned capabilities rather than silently pretending to
work.

Licensed under GPL-3.0-only. See [LICENSE](LICENSE).
