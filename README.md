# Bliss 'Em All

Bliss 'Em All is a Lyrion Music Server plugin for auditable playlist
optimization powered by Bliss. It will depend on a compatible BlissMixer
installation for `bliss.db` and captured scoring settings, plus the platform's
`bliss-playlist-optimizer` executable. The current bundled optimizer requires
the learned matrix captured by the compatible BlissMixer fork.

The current development milestone is installable on ARM64 LMS systems. It
exposes the complete planned UX shell while connecting three safe writable paths:
**Optimize order > Reorder only**, **Extend automatically**, and **Add exactly
N tracks**. All use
per-job Adaptive and repeat settings initialized from BlissMixer defaults,
background native Preview, result review, and explicit creation of a new copy.
Automatic extension exposes a per-job bridge budget and trigger percentile;
exact-count extension exposes a validated per-job count and never accepts a
partial result. Every future-only item is visibly marked **Not connected yet** and
cannot start a job. See
[`docs/UX_STATUS.md`](docs/UX_STATUS.md) for the feature matrix.

## Try the live workflow

After installing the `BlissEmAll` directory and restarting LMS, open
**Extras > Bliss 'Em All**. Select a saved playlist, adjust its per-job Adaptive
parameters and repeat windows, choose whether to optimize the source-track order,
then choose no additions, automatic additions, or an exact number of additions,
choose **Create optimized copy**, enter its new name, and select **Run read-only
preview**. Use a zero artist or album look-back to disable that constraint for a
single-artist or single-album collection. Automatic extension may add zero up
to the configured bridge budget and reports every transition decision. The
result page refreshes while the native job runs and presents prominent
running, success, optimization-failure, and copy-failure messages. Preview is
read-only. Exact-count is currently bounded to one addition in each internal
optimized transition, so its UI limit is `S - 1` for `S` source tracks. Only
the separate **Create optimized copy** action on a completed
result writes anything.

The **Musical context window (previous tracks)** controls the rolling history
used by directional Adaptive scoring. A bridge C between A and B is evaluated
as history ending in A to C, then updated history ending in C to B. Additional
route-search attempts are an advanced, deterministic effort control used only
when source tracks may move; more attempts may improve the route at additional
CPU cost.

Status banners use explicit foreground/background pairs rather than inheriting
the surrounding skin's text color, so warnings, failures, running state, and
success remain readable in both light and dark hosts. The registered Extras
icon follows Material's monochrome marker convention and resolves to its
`timeline` glyph instead of the generic extension icon; classic/plugin
metadata receives the packaged transparent monochrome route asset.

Requests, native output, and stderr are kept beneath the LMS cache in
`blissemall/jobs`. Version `0.8.0` also keeps one checksum-protected decoded
library cache under `blissemall/library-cache`, keyed by the guarded `bliss.db`
file identity. Cold jobs bulk-load the library with one SQLite query; warm jobs
reuse the database hash, integrity result, and decoded features. Completion
logs show wall/native time and cache state, while debug logging adds per-stage
native milliseconds. Creation uses Lyrion's core M3U formatter, exclusively
creates a new file, creates the LMS playlist object, and verifies both catalog
and file order before reporting success. A blank copy name is derived from the
decoded playlist filename, preserving Unicode such as emoji, and receives the
next free numbered suffix when necessary. Explicit existing names are rejected,
and the source playlist is never changed.

Addition jobs also use a deterministic 256-track internal-gap shortlist before
repeated evolving-state bridge scoring. It reserves endpoint-local semantic
evidence and fills the rest from the strict initial-gap dynamic Adaptive rank.
Final insertion decisions still
come from dynamic two-leg Adaptive scoring and the normal semantic, repeat,
membership, and acoustic gates; the shortlist is a performance bound, not a
separate mixing strategy.

Automatic and exact-count bridge discovery currently use the local Bliss-only fallback. The
optional Last.fm and ListenBrainz evidence adapters remain visibly unconnected;
their absence never blocks acoustic extension.

The plugin owns LMS menus, preferences, background jobs, optional semantic
providers, reports, and atomic playlist persistence. The native optimizer will
remain network-free.

Licensed under GPL-3.0-only. See `LICENSE`.
