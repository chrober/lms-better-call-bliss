# Playlist Breaking Bad? Better Call Bliss.

<p align="center">
  <img src="docs/images/better-call-bliss-banner.png" alt="Playlist Breaking Bad? Better Call Bliss." width="900">
</p>

**Better Call Bliss** is a Lyrion Music Server plugin that turns a saved
playlist or a current player queue snapshot into a smoother listening journey.
It can reorder the existing songs, insert suitable bridge tracks, preserve the
original order while filling its gaps, extend a short source list to a chosen
length, or rebuild the upcoming part of a live queue. Every job is previewed before
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
- Adds exactly a requested number of tracks, reaches a final track count, or doubles the track count.
- Preserves the existing order when requested and inserts tracks only in gaps.
- Uses dynamic Adaptive Bliss similarity, optional learned preferences,
  per-job variation, and optional Last.fm similar-track and similar-artist guidance.
- Uses a saved playlist, a full player queue, only upcoming queue tracks, or the
  current-plus-upcoming queue segment as input.
- Offers three destination shortcuts on a local track in this menu order.  
  **Bliss me there...** keeps the current song and playback state while replacing  
  only the upcoming queue with a route to the destination. **Bliss me there... and  
  back again!**  
  inserts an excursion from the current song through the selected track and back  
  to the unchanged upcoming queue. **Bliss me there... when we're through!** builds  
  from the queue end and appends its route. All three validate their captured live anchors  
  before changing the queue. Recent entries are immutable history rather than  
  route members, so legitimate repeats already heard do not invalidate the request.  
  Normal or Cautious automatic bridge handling controls how learned/Static  
  disagreement affects direct acceptance and whole-route ranking. Fast, Balanced,  
  and Thorough trade runtime for progressively wider searches.  
- Shows a read-only preview and diagnostics before creating a verified copy,
  overwriting the source playlist, or sending the result to a player queue.
- Can replace, append to, play next, or replace only the upcoming part of a
  player queue, with optional start playback.
- Never modifies bliss.db or the source audio files.

## Relationship to BlissMixer

Better Call Bliss deliberately builds on and credits the original
[lms-blissmixer](https://github.com/CDrummond/lms-blissmixer) feature
**Create bliss mix**. That BlissMixer action already generates immediate
Bliss-based mixes from a selected track, artist, album, or genre context. Better
Call Bliss is a companion workflow around the same Bliss ecosystem: it previews
auditable saved-playlist and player-queue transformations, exposes per-job
constraints, and lets the user choose whether to save, overwrite, or send the
accepted result to a player.

See [Playlist optimization modes and options](ALGORITHMS.md) for reader-friendly
explanations, technical flowcharts, option ranges, and the exact boundary
between working and planned modes. See [UX status](docs/UX_STATUS.md) for the
complete feature matrix.

## Requirements

- Lyrion Music Server 8.5 or newer.
- A compatible original
  [lms-blissmixer](https://github.com/CDrummond/lms-blissmixer) installation.
  Better Call Bliss reuses its analyzed library and configured base defaults
  without modifying the plugin.
- A completed Bliss analysis that produced a readable bliss.db in the Lyrion
  preferences directory.
- [BlissMixerExt](https://github.com/chrober/lms-blissmixer-ext) is optional.
  When enabled, it contributes `learned_matrix.json`, its learned-blend
  preference, and—starting with BlissMixerExt 0.3.0—its Last.fm similar-track
  guidance preference. Better Call Bliss consumes that track-guidance value
  instead of storing a duplicate global setting. It does not treat a stray
  matrix file as active personalization when BlissMixerExt is unavailable.
- A readable `learned_matrix.json` is optional. When present through
  BlissMixerExt, Adaptive can blend it with dynamic variance. When absent,
  Better Call Bliss follows the BlissMixer
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

## Logging and diagnostics

Lyrion exposes the plugin log category `plugin.bettercallbliss`. Its output is
grouped by the stable `job=<id>` prefix so one preview can be followed from the
user action through provider collection, native optimization, review, and final
playlist or queue output.

At **Information** level, Better Call Bliss reports the source and destination,
effective mixing and repeat settings, immutable history and route members,
Last.fm request health,
selected additions and their evidence type, the audible final route, acoustic
quality, native runtime, and verified output. This is intended to explain what
the job did without enumerating the candidate library.

At **Debug** level it additionally reports request/result/progress artifact
paths, stable LMS identities and URLs, native stage timings, detailed Last.fm
evidence for each selected addition, and every adjacent **Bliss me there...**
leg. When learned and Static acoustic models are both available, the governing
measurement and the other model's measurement are shown separately for every
final leg. Under Normal caution the second view is advisory. Under Cautious it
participates in route acceptance and ranking.

The native optimizer publishes these secondary measurements in
`selection_preview.route_quality.secondary_models` and records configured
caution, disagreement magnitude, and whether it triggered a search. Older artifacts
without that optional field remain supported; Better Call Bliss simply omits
the secondary comparison.

## Release and publishing workflow

GitHub Actions workflow `.github/workflows/release.yml` builds a release package
without committing native binaries to this repository:

1. Runs the lightweight Perl regression suite from `tests/`. The suite stubs
   LMS/LastMix APIs and checks request JSON typing, Last.fm evidence, per-job
   option normalization, localization metadata, and source-package hygiene.
2. Reads the pinned `bliss-playlist-optimizer` release from
   `BetterCallBliss/Bin/SOURCE.md`, unless an `optimizer_release` override is
   supplied manually.
3. Downloads the published optimizer binaries for `x86_64-linux`,
   `aarch64-linux`, `armhf-linux`, `mac`, and `windows` from that release and
   verifies their `.sha256` files.
4. Copies those binaries into the matching `BetterCallBliss/Bin/<platform>/`
   folders only inside the release workspace.
5. Creates `lms-better-call-bliss-<version>.zip` plus SHA-1 and SHA-256 files.
6. Publishes the GitHub Release and, unless disabled, updates
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
  The tests stub the relevant LMS/LastMix APIs and check request JSON typing,
  Last.fm evidence handling, per-job option normalization, localization
  metadata, and source-package hygiene. GitHub Actions runs them on push, pull
  request, and before release packaging. This folder is not installed as runtime
  plugin UI; it is committed so future changes can catch these integration
  regressions.
- `docs/`, `ALGORITHMS.md`, and `README.md` are project documentation and are
  not required for the plugin to run.

## Component boundary

~~~mermaid
flowchart LR
    LMS["Lyrion saved playlist"] --> P["Better Call Bliss plugin"]
    Q["Current player queue snapshot"] --> P
    BM["Original lms-blissmixer<br/>settings and bliss.db"] --> P
    BME["Optional BlissMixerExt<br/>learned matrix, blend, and track guidance"] -.-> P
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
extension. Disabled controls
in the UI describe planned capabilities rather than silently pretending to
work.

Licensed under GPL-3.0-only. See [LICENSE](LICENSE).
