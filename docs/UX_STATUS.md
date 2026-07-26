# UX contract and implementation status

This document describes the complete intended **Bliss 'Em All** interaction
model and the exact boundary of the current `0.7.0` UX shell. The shell is
deliberately broader than the backend so the remaining implementation can be
connected without redesigning the user journey.

The UI uses three explicit states:

- **Working**: the action executes real plugin/native behavior.
- **Partial**: useful data is real, but lifecycle or persistence is incomplete.
- **Not connected yet**: the planned control or screen is visible, but cannot
  start a job or mutate data.

Items marked **Not connected yet** are informational. They must not silently
fall through to either working mode.

## Entry points

| Entry point | Status | Current behavior |
| --- | --- | --- |
| Extras > Bliss 'Em All | Working | Opens the rich per-job editor and result area. |
| Extensions contribution icon | Working | Explicitly registers the packaged 512x512 transparent monochrome route icon. Material recognizes its `MTL_icon_timeline` marker and renders the theme-colored `timeline` glyph instead of the generic puzzle piece. |
| Applications / My Apps > Bliss 'Em All | Removed | The OPML adapter cannot provide the required portable multi-field form. |
| Saved-playlist context > Bliss 'Em All... | Partial | Visible informational shortcut; directs the user to Extras. |
| Track context > Bliss me there... | Not connected yet | Describes the planned route-to-track capability; starts no job. |
| Full EN/DE menu localization | Not connected yet | The Extras shell is English-first; settings labels have EN/DE strings. |

## Optimization wizard

| Step or option | Status | Contract |
| --- | --- | --- |
| Select saved playlist | Working | Lists LMS saved playlists with at least two tracks. |
| Optimize source order | Working for no additions, automatic additions, and exact-count additions | Original tracks may move. |
| Preserve source order | Not connected yet | Original sequence remains fixed; additions may occupy gaps or explicitly enabled endpoints only. |
| No additional tracks | Working | Uses every original track exactly once and inserts none; unavailable with preserved order because that combination is a no-op. |
| Add automatically | Working | Reorders the source, then adds up to the per-job budget only where the contextual trigger, acoustic-improvement, uniqueness, and repeat gates pass. It may add zero. |
| Add exactly N tracks | Working | Adds exactly the validated user-entered number of unique eligible tracks or fails without returning a partial playlist. This first slice permits one addition per internal optimized transition and no endpoint additions, so `1 <= N <= S - 1`. |
| One bridge per source-track transition | Not connected yet | Adds one track in each of the `S - 1` original transitions, yielding `2S - 1` tracks. |
| Target length | Not connected yet | Adds tracks until the exact total `T >= S` is reached. |
| Double length | Not connected yet | Adds exactly `S` tracks, yielding `2S` tracks. |
| Numeric editor for N/T | Working for N | Exact-count input is validated as 1-100 server-side and constrained to `S - 1` for the selected playlist in both the UI and request builder. Target-length input remains future work. |
| Musical context window (previous tracks) | Working, per job | Rolling preceding-track count used for every directional Adaptive leg. A bridge C between A and B is scored as history-to-C and updated-history-with-C-to-B; variance-based weighting begins with two available context tracks. |
| Learned-matrix blend | Working, per job | Validated as 0-100 and passed to this job's native request. |
| Artist/album/track look-back | Working, per job | Initialized from BlissMixer; zero disables the corresponding constraint. |
| Additional route-search attempts | Working, per job | Validated as 0-500, grouped under Advanced, and used only when source order may change. Zero retains the built-in fixed starts. |
| Relevance-aware controls | Working | Automatic and exact-count inputs are enabled only for their modes; the exact limit and resulting size follow the selected playlist; route attempts are disabled for preserved order; guaranteed no-op preserved combinations disable submission and fail server validation if bypassed. |
| Accessible status feedback | Working | Warning, error, success, and running/info banners use explicit high-contrast foreground/background pairs; theme text color is retained for secondary notes and disabled hints. |
| Automatic bridge budget | Working, per job | Validated as 0-100; limits successful additions rather than candidate analysis. |
| Bridge trigger percentile | Working, per job | Validated as 0-100; only direct gaps strictly above this frozen contextual percentile are eligible. |
| Static weighted / random-forest strategy | Not connected yet | Visible but disabled because native route currently accepts Adaptive only. |
| Review | Working for all three connected modes | The submitted form and result retain the job-specific values. |
| Run preview | Working for all three connected modes | Launches the native optimizer asynchronously and never writes a playlist. |

`S` is the original source-track count. Current automatic bridge discovery uses
local Bliss evidence. Once optional semantic providers are connected,
similar-artist evidence local to transition `A -> B` will be preferred;
evidence from the full source artist pool is only a fallback.

## Result and job UX

| Screen or action | Status | Current behavior |
| --- | --- | --- |
| Active preview | Partial | Real running job, retained only in LMS process memory; the page polls automatically and keeps a manual refresh link. |
| Result | Partial | Real completed/failed job, lost on LMS restart. |
| Refresh result | Working | Automatically re-reads the selected in-memory job every 1.5 seconds while running; manual refresh remains available. |
| Cancel preview | Not connected yet | No cancellable native-process handle is exposed. |
| Result summary | Working | Prominently reports running, Preview success/failure, and copy success/failure, then shows selected strategy, objective, worst transition, and constraint validation. |
| Proposed order | Working | Shows every original track and its original position. |
| Additions and reasons | Working for automatic and exact-count extension | Labels every added local track, its original endpoints, direct-gap percentile, and evidence tier/pool; automatic zero-addition results are explicit. Exact-count also reports requested/final counts and bounded-search capacity. |
| Transition summary | Partial | Aggregate reorder diagnostics are real; automatic and exact-count extension show one decision/reason per original gap, while a general per-leg drill-down remains open. |
| Warnings | Partial | Repeat validation and read-only safety are real; provider warnings await providers. |
| Full report | Partial | In-memory artifact identity is shown; durable report storage and download are not connected. |
| Create optimized copy | Working | Separate post-Preview action writes and verifies a new LMS playlist. Blank names preserve Unicode from the decoded source filename and choose the next free numbered suffix; explicit collisions fail visibly and safely. |
| Overwrite source | Not connected yet | Captured for UX continuity but never mutates the source. |
| Change options and rerun | Not connected yet | Draft restoration is not implemented. |
| Discard result | Not connected yet | Session results expire naturally on LMS restart. |

## Settings

The Extras editor initializes scoring and repeat fields from BlissMixer. The
submitted values belong to that job only and never update BlissMixer's global
preferences. The current bundled optimizer supports only Adaptive routing and
requires a learned matrix; unsupported strategies are disabled and labeled.

**Additional route-search attempts**, both output suffixes, automatic bridge budget, and
automatic trigger percentile supply defaults for new jobs. Every value that
affects optimization is copied into and may be overridden by the job. The
following settings are persisted to establish their future contract but are labeled
**not connected yet** on the settings page:

- Last.fm and ListenBrainz enablement;
- semantic cache freshness and stale-offline lifetime; and
- persistent report retention.

Last.fm and ListenBrainz remain optional. Once connected, timeouts, provider
errors, malformed responses, rate limits, and missing Internet access must
degrade to cached or local Bliss evidence rather than fail optimization.

## Safety boundary

Version `0.7.0` keeps Preview read-only and permits only an explicit,
post-Preview **Create optimized copy** mutation. The writer uses Lyrion's core
M3U serializer, verifies the same-directory temporary file, exclusively claims
the final path without overwrite semantics, copies the verified bytes, creates
the LMS catalog object, and compares both catalog and final-file order with the
optimizer result. It rejects an explicit existing name without touching it,
automatically chooses a free numbered name only when the field was left blank,
and removes only artifacts created by the failed attempt. Lyrion's playlist
object is updated directly, so this workflow does not depend on a library scan.
Source overwrite, remaining extension modes, and every other shell-only action remain
unreachable. Automatic and exact-count extension additionally require the native source
membership proofs, an unchanged database file identity during the job, exact
source subsequence preservation, unique final membership, and successful
read-only resolution of every proposed bridge to a local LMS track.
Exact-count additionally requires the artifact's requested count to match the
job, an explicit feasible state, and exactly `N` resolved bridges. A native
infeasibility proof becomes a visible failed Preview and is never normalized
or persisted as a partial sequence.

## piCorePlayer development deployment

For a manually deployed development build, use piCorePlayer's supported manual
plugin root:

```text
<LMS cache>/Plugins/BlissEmAll
```

On the current server this resolves to
`/mnt/mmcblk0p2/tce/slimserver/Cache/Plugins/BlissEmAll`. Do not hand-copy a
development build into `Cache/InstalledPlugins/Plugins`: that directory is
owned by LMS's extension manager, and an unregistered folder can be removed on
restart. Production installation remains the planned plugin ZIP plus extension
repository flow.
