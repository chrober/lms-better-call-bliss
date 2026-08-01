# Playlist Breaking Bad? Better Call Bliss.

<p align="center">
  <img src="docs/images/better-call-bliss-banner.svg" alt="Playlist Breaking Bad? Better Call Bliss." width="900">
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

See [Mixing strategies and options](ALGORITHMS.md) for plain-English
explanations, technical flowcharts, option ranges, and the exact boundary
between working and planned modes. See [UX status](docs/UX_STATUS.md) for the
complete feature matrix.

## Requirements

- Lyrion Music Server 8.5 or newer.
- A compatible
  [lms-blissmixer](https://github.com/chrober/lms-blissmixer) installation,
  currently the learned-matrix-enabled fork used by this project. Better Call
  Bliss deliberately reuses its analyzed library and configured defaults
  without modifying the plugin.
- A completed Bliss analysis that produced a readable bliss.db in the Lyrion
  preferences directory.
- A readable learned_matrix.json. The current bundled optimizer requires it,
  even though the per-job blend can reduce its influence to zero.
- A configured local Lyrion music folder whose tracks correspond to bliss.db.
- A bliss-playlist-optimizer binary for the server platform. Development
  packages currently bundle the tested ARM64 Linux build.

[LastMix](https://github.com/AF-1/lms-lastmix) is optional. When installed and
enabled, it supplies anonymous Last.fm similar-artist evidence. Missing
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

## Component boundary

~~~mermaid
flowchart LR
    LMS["Lyrion saved playlist"] --> P["Better Call Bliss plugin"]
    BM["lms-blissmixer settings<br/>bliss.db and learned matrix"] --> P
    LM["Optional LastMix<br/>Last.fm artist evidence"] --> P
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
