# UX contract and implementation status

This document describes the complete intended **Better Call Bliss** interaction
model and the exact boundary of the current `0.14.3` UX shell. The shell is
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
| Extras > Better Call Bliss | Working | Opens the rich per-job editor and result area. The page title uses the full tagline, **Playlist Breaking Bad? Better Call Bliss.** |
| Extensions contribution icon | Working | Explicitly registers the packaged 512x512 transparent monochrome route icon. Material recognizes its `MTL_icon_timeline` marker and renders the theme-colored `timeline` glyph instead of the generic puzzle piece. |
| Applications / My Apps > Better Call Bliss | Removed | The OPML adapter cannot provide the required portable multi-field form. |
| Saved-playlist context > Better Call Bliss... | Partial | Visible informational shortcut; directs the user to Extras. |
| Track context > Bliss me there... | Not connected yet | Describes the planned route-to-track capability; starts no job. |
| Full EN/DE menu localization | Not connected yet | The Extras shell is English-first; settings labels have EN/DE strings. |

## Optimization wizard

| Step or option | Status | Contract |
| --- | --- | --- |
| Select saved playlist | Working | Lists LMS saved playlists with at least two tracks. |
| Optimize source order | Working for no additions, automatic additions, exact-count additions, and seed growth | Original tracks may move. Seed growth always routes the complete final membership. |
| Preserve source order | Working for automatic and exact-count additions | Every original track remains an immutable anchor in its input order. This UI slice fills internal gaps only, with at most one added track per gap; endpoint controls remain unavailable. |
| No additional tracks | Working | Uses every original track exactly once and inserts none; unavailable with preserved order because that combination is a no-op. |
| Add automatically | Working | With optimized order, reorders the source before examining gaps; with preserved order, examines only the original gaps. It adds up to the per-job budget where the contextual trigger, acoustic-improvement, uniqueness, and repeat gates pass, and may add zero. |
| Add exactly N tracks | Working | Adds exactly the validated user-entered number of unique eligible tracks or fails without returning a partial playlist. Both ordering policies permit one addition per internal source-track transition and no endpoint additions, so `1 <= N <= S - 1`. |
| Grow from these seeds | Working | Keeps all `S` source tracks exactly once, uses their complete immutable set as the Adaptive relevance reference, selects exactly `T - S` LMS-local analyzed additions under repeat-window capacity, and routes the complete `T`-track membership. The default target is 25. |
| One bridge per source-track transition | Not connected yet | Adds one track in each of the `S - 1` original transitions, yielding `2S - 1` tracks. |
| Target length | Not connected yet | Adds tracks until the exact total `T >= S` is reached. |
| Double length | Not connected yet | Adds exactly `S` tracks, yielding `2S` tracks. |
| Numeric editor for N/T | Working for exact additions and seed-growth target | Exact-count input is validated as 1-100 and constrained to `S - 1`. Seed-growth target is validated as 3-500 and must exceed `S`; the UI reports `S` seeds plus `T - S` additions. The generic bridge target-length preset remains future work. |
| Musical context window (previous tracks) | Working, per job | Rolling preceding-track count used for every directional Adaptive leg. A bridge C between A and B is scored as history-to-C and updated-history-with-C-to-B; variance-based weighting begins with two available context tracks. |
| Learned-matrix blend | Working, per job | Validated as 0-100 and passed to this job's native request. With two or more context tracks, 0 means pure variance weighting. If no learned matrix is available, Adaptive uses variance for multi-track contexts and Static BlissMixer weights for one-track contexts. |
| Artist/album/track look-back | Working, per job | Initialized from BlissMixer; zero disables the corresponding constraint. |
| Additional route-search attempts | Working, per job | Validated as 0-500, grouped under Advanced, and used only when source order may change. Zero retains the built-in fixed starts. |
| Variation | Working, per job | Validated as 0-100 and applied downstream of the selected scoring strategy. Zero preserves strict best-match behavior; higher values use seeded weighted sampling inside a bounded top acoustic pool. A blank generation seed changes each run, while an explicit/reported seed reproduces it. |
| Last.fm guidance | Working, optional and per job | Requires enabled LastMix and queries similar tracks and artists for the complete distinct source set. Similar-track and similar-artist guidance are separate 0-100 bounded influences, both defaulting to 75. They rerank only local, repeat-safe, Bliss-qualified candidates and degrade to Bliss on unavailable, partial, malformed, offline, or API-failure states. |
| Relevance-aware controls | Working | The Extras editor shows only sections relevant to the selected source-order and addition mode. Hidden sections keep their values for mode switching, selected-mode inputs remain submitted for draft restoration, exact and target counts follow the selected playlist, seed growth forces complete-membership order optimization, and guaranteed no-op combinations disable submission and fail server validation if bypassed. Bounded numeric controls use the same `sliderInput_min_max_step` enhancement classes as BlissMixer settings where practical. |
| Accessible status feedback | Working | Warning, error, success, and running/info banners force explicit high-contrast foreground/background pairs on both containers and nested text; theme text color is retained only for secondary notes and disabled hints. |
| LMS scan coordination | Working | Preview pauses while LMS reports an active library scan, explains that the catalog is changing, and retries the page automatically until the scan finishes. |
| Automatic bridge budget | Working, per job | Validated as 0-100; limits successful additions rather than candidate analysis. |
| Bridge trigger percentile | Working, per job | Validated as 0-100; only direct gaps strictly above this frozen contextual percentile are eligible. |
| Internal bridge shortlist | Working, implementation-level | Addition jobs deterministically narrow each large internal-gap pool to 256 high-recall candidates before strict scoring. Endpoint-local semantic evidence is reserved; strict dynamic Adaptive scoring and all safety gates remain authoritative. This is intentionally not a job control in the current UX. |
| LMS-local bridge inventory | Working, safety gate | Every addition job freezes a checksum-protected allowlist of usable Bliss rows that resolve to current non-remote LMS audio tracks. Non-allowlisted rows are removed before semantic ranking, shortlisting, and scoring; post-result LMS resolution remains mandatory. |
| Static weighted strategy | Working, per job | Uses BlissMixer's four static metric sliders expanded to the 23 Bliss feature weights; the same fixed matrix is used for every contextual distance. |
| Extended Isolation Forest strategy | Not connected yet | Visible but disabled because native playlist routing does not implement Forest scoring yet. |
| Review | Working for all connected combinations | The submitted form and result retain the job-specific values and explicitly state whether source order was optimized or preserved. |
| Run preview | Working for all connected combinations | Launches the native optimizer asynchronously and never writes a playlist. |

`S` is the original source-track count. Last.fm track or artist evidence local to a transition `A -> B` is preferred; evidence from the complete original source artist pool is only a fallback. ListenBrainz remains later.

## Result and job UX

| Screen or action | Status | Current behavior |
| --- | --- | --- |
| Active preview | Partial | Real running job, retained only in LMS process memory; the page polls automatically and keeps a manual refresh link. |
| Result | Partial | Real completed/failed job, lost on LMS restart. |
| Refresh result | Working | Automatically re-reads the selected in-memory job every 1.5 seconds while running; manual refresh remains available. |
| Cancel preview | Not connected yet | No cancellable native-process handle is exposed. |
| Result summary | Working | Prominently reports running, Preview success/failure, and copy success/failure, then shows selected strategy, objective, worst transition, and constraint validation. |
| Proposed order | Working | Shows every original track and its original position. |
| Additions and reasons | Working for automatic, exact-count, and seed-growth extension | Bridge modes label every added local track, original endpoints, direct-gap percentile, and evidence tier/pool. Seed growth labels each addition with its distance from the fixed full-seed Adaptive reference and reports seed/addition/final counts. |
| Seed-growth selection and route diagnostics | Working | Reports best/mean/furthest fixed-seed Adaptive relevance separately from final-route strategy, transition sum, worst transition, objective, and arc error. A collapsible acceptance section confirms exact target, every seed once, local additions, unique membership, and repeat-window compliance. |
| Transition summary | Partial | Aggregate reorder diagnostics are real; automatic and exact-count extension show one decision/reason per original gap, while a general per-leg drill-down remains open. |
| Warnings | Partial | Repeat validation, read-only safety, Last.fm provider fallback states, and a service-wide-error circuit breaker are real; a complete provider/cache dashboard remains open. |
| Full report | Partial | In-memory artifact identity is shown; durable report storage and download are not connected. |
| Non-LMS Bliss-row audit | Working | After the first addition job, Extras shows the current excluded-row count and persistent ledger path. The private JSON ledger retains current/resolved state, reason, row identity, metadata, and first/last-seen observations across LMS restarts. Existing case-variant duplicates are identified separately and include the related exact LMS identity. |
| Create optimized copy | Working | Separate post-Preview action writes and verifies a new LMS playlist. Blank names preserve Unicode from the decoded source filename and choose the next free numbered suffix; explicit collisions fail visibly and safely. |
| Overwrite source | Not connected yet | Captured for UX continuity but never mutates the source. |
| Change options and rerun | Working for in-memory jobs | Polling, success, failure, and copy-action pages restore every normalized job value into the editor; users can adjust those values and start another Preview. Drafts do not survive an LMS restart. |
| Discard result | Not connected yet | Session results expire naturally on LMS restart. |

## Settings

The Extras editor initializes scoring and repeat fields from BlissMixer. The
submitted values belong to that job only and never update BlissMixer's global
preferences. The bundled optimizer supports Adaptive and Static routing. A
learned matrix is optional: Adaptive blends it when supplied and otherwise uses
variance weighting for multi-track contexts plus Static BlissMixer weights for
one-track contexts. Extended Isolation Forest remains disabled and labeled.

**Additional route-search attempts**, both output suffixes, automatic bridge budget, and automatic trigger percentile supply defaults for new jobs. Bounded settings use the same slider-enhanced numeric input convention as BlissMixer where practical. Every value that affects optimization is copied into and may be overridden by the job. The following settings are persisted to establish their future contract but are labeled **not connected yet** on the settings page:

- ListenBrainz enablement;
- semantic cache freshness and stale-offline lifetime; and
- persistent report retention.

Last.fm is optional and uses LastMix's anonymous access. Its plugin-wide enable
enable switch is complemented by separate per-job track and artist guidance defaults.
Timeouts, provider errors, malformed responses, rate limits, and missing
Internet access degrade to local Bliss evidence rather than fail optimization.
ListenBrainz remains optional and is deliberately deferred.

## Safety boundary

Version `0.14.3` keeps Preview read-only and permits only an explicit,
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
The frozen LMS-local allowlist is required for plugin addition jobs and is applied before the native candidate search. It is bound to the exact guarded `bliss.db` identity; an invalid checksum, wrong schema, unknown row, database mismatch, or missing source membership fails the request. The later per-bridge resolution remains a separate fail-closed proof if LMS membership changes after inventory capture.
Preserve-order jobs additionally require the artifact policy to match the job
and the selected base-route IDs to equal the source IDs in exact order.
Exact-count additionally requires the artifact's requested count to match the
job, an explicit feasible state, and exactly `N` resolved bridges. A native
infeasibility proof becomes a visible failed Preview and is never normalized
or persisted as a partial sequence.
Seed growth additionally requires an exact target match, unique final membership, every source ID exactly once, exactly `T - S` resolved additions, and selection details for every added Bliss row. Its native proof block must also affirm local-inventory membership and artist/album/track repeat compliance before the plugin accepts the result. Added tracks never enter the relevance anchor; they affect only complete-membership routing.

## piCorePlayer development deployment

For a manually deployed development build, use piCorePlayer's supported manual
plugin root:

```text
<LMS cache>/Plugins/BetterCallBliss
```

On the current server this resolves to
`/mnt/mmcblk0p2/tce/slimserver/Cache/Plugins/BetterCallBliss`. Do not hand-copy a
development build into `Cache/InstalledPlugins/Plugins`: that directory is
owned by LMS's extension manager, and an unregistered folder can be removed on
restart. Production installation remains the planned plugin ZIP plus extension
repository flow.
