# UX contract and implementation status

This document describes the complete intended **Better Call Bliss** interaction
model and the exact boundary of the current `0.15.0` / `extras-job-editor-v22` UX shell. The shell is
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
| Saved-playlist context > Better Call Bliss... | Working | Opens the rich job editor with the selected saved playlist preselected. In Material this appears as an item menu/More action rather than a permanent inline row button. |
| Track context > Bliss me there... | Working | Starts a destination route in the background using saved defaults, without opening Extras or requiring an Accept button. Automatic chooses the shortest acceptable route from zero through the configured maximum intermediates; Exact requires its configured count. A successful job automatically appends only the suffix after a live-tail check; a stale or infeasible job appends nothing and remains reviewable in recent previews. |
| Full EN/DE menu localization | Not connected yet | The Extras shell is English-first; settings labels have EN/DE strings. |

## Optimization wizard

| Step or option | Status | Contract |
| --- | --- | --- |
| Select saved playlist | Working | Lists LMS saved playlists with at least two tracks. |
| Optimize source order | Working for no additions, difficult-transition improvements, and Extend playlist | Original tracks may move. Extend playlist routes the complete final membership when this policy is selected. |
| Preserve source order | Working for difficult-transition improvements and Extend playlist | Every original track remains an immutable anchor in its input order. Difficult-transition improvements inspect source gaps. Extend playlist keeps the source order as anchors and places the selected additions around them when repeat windows can be satisfied. |
| Additional-track purpose | Working | The visible editor asks for the purpose first: no additions, improve difficult transitions, or Extend playlist. Extend playlist maps to the native fixed-source extension request after calculating the requested final size. The dedicated destination-route mode is used only by Bliss me there; general playlist additions continue to use their own listener-facing purposes. |
| No additions | Working | Uses every original track exactly once and inserts none; rejected with preserved order because that combination is a guaranteed no-op. |
| Improve difficult transitions | Working | Formerly shown as Add automatically. With optimized order, reorders the source before examining gaps; with preserved order, examines only the original gaps. It adds up to the per-job budget where the contextual trigger, acoustic-improvement, uniqueness, and repeat gates pass, and may add zero. |
| Extend playlist | Working | Shows a second amount selector for Add exactly N tracks, Reach final track count, or Double track count. The selected amount is honored through fixed-source membership selection rather than being capped by internal source gaps. |
| Add exactly N tracks | Working under Extend playlist | Adds exactly the validated user-entered number of unique eligible local tracks or fails without returning a partial playlist. The visible Extend playlist path is not limited by `S - 1` gaps. |
| Reach target track count | Working under Extend playlist | User enters the desired final track count. The plugin derives `N = T - S` and runs fixed-source membership selection. |
| Add N bridge tracks per source transition | Not connected yet | Planned placement preset that adds the same configured number of tracks in each of the `S - 1` original transitions. `N = 1` yields `2S - 1` tracks. |
| Target duration | Not connected yet | Duration-based targets need tolerance and duration-quality tradeoffs; this is deliberately separate from track-count targets. |
| Double track count | Working under Extend playlist | Adds exactly `S` local tracks, yielding `2S` tracks, through fixed-source membership selection. |
| Double duration | Not connected yet | Duration-based doubling remains future work. |
| Numeric editor for N/T | Working for Extend playlist targets | Exact-addition input is validated as 1-100 and converted to final size `S + N`. Target track count is validated as 3-500 and must exceed `S`. Double count is disabled when `2S` would exceed the 500-track target limit. |
| Musical context window (previous tracks) | Working, per job | Rolling preceding-track count used for every directional Adaptive leg. A bridge C between A and B is scored as history-to-C and updated-history-with-C-to-B; variance-based weighting begins with two available context tracks. |
| Learned-matrix blend | Working, per job | Validated as 0-100 and passed to this job's native request. With two or more context tracks, 0 means pure variance weighting. If no learned matrix is available, Adaptive uses variance for multi-track contexts and Static BlissMixer weights for one-track contexts. |
| Artist/album/track look-back | Working, per job | Initialized from BlissMixer; zero disables the corresponding constraint. |
| Additional route-search attempts | Working, per job | Validated as 0-500, grouped under Advanced, and used only when source order may change. Zero retains the built-in fixed starts. |
| Variation | Working, per job | Validated as 0-100 and applied downstream of the selected scoring strategy. Zero preserves strict best-match behavior; higher values use seeded weighted sampling inside a bounded top acoustic pool. A blank generation seed changes each run, while an explicit/reported seed reproduces it. |
| Last.fm guidance | Working, optional and per job | Requires enabled LastMix and queries similar tracks and artists for the complete distinct source set. Similar-track and similar-artist guidance are separate 0-100 bounded influences, both defaulting to 75. They rerank only local, repeat-safe, Bliss-qualified candidates and degrade to Bliss on unavailable, partial, malformed, offline, or API-failure states. |
| Relevance-aware controls | Working | The Extras editor shows only sections relevant to the selected source-order and addition purpose. Count-specific fields appear only when Extend playlist requires them. Hidden sections keep their values for mode switching, selected-mode inputs remain submitted for draft restoration, exact and target counts follow the selected source snapshot, and guaranteed no-op combinations disable submission and fail server validation if bypassed. Bounded numeric controls use the same `sliderInput_min_max_step` enhancement classes as BlissMixer settings where practical. |
| Accessible status feedback | Working | Warning, error, success, and running/info banners force explicit high-contrast foreground/background pairs on both containers and nested text; theme text color is retained only for secondary notes and disabled hints. |
| LMS scan coordination | Working | Preview pauses while LMS reports an active library scan, explains that the catalog is changing, and retries the page automatically until the scan finishes. |
| Automatic bridge budget | Working, per job | Validated as 0-100; limits successful additions rather than candidate analysis. |
| Bridge trigger percentile | Working, per job | Validated as 0-100; only direct gaps strictly above this frozen contextual percentile are eligible. |
| Internal bridge shortlist | Working, implementation-level | Addition jobs deterministically narrow each large internal-gap pool to 256 high-recall candidates before strict scoring. Endpoint-local semantic evidence is reserved; strict dynamic Adaptive scoring and all safety gates remain authoritative. This is intentionally not a job control in the current UX. |
| LMS-local bridge inventory | Working, safety gate | Every addition job freezes a checksum-protected allowlist of usable Bliss rows that resolve to current non-remote LMS audio tracks. Non-allowlisted rows are removed before semantic ranking, shortlisting, and scoring; post-result LMS resolution remains mandatory. |
| Static weighted strategy | Working, per job | Uses BlissMixer's four static metric sliders expanded to the 23 Bliss feature weights; the same fixed matrix is used for every contextual distance. |
| Extended Isolation Forest strategy | Not connected yet | Visible but disabled because native playlist routing does not implement Forest scoring yet. |
| Review | Working for all connected combinations | The submitted form and result retain the job-specific values and explicitly state whether source order was optimized or preserved. |
| Run preview | Working for all connected combinations | Launches the native optimizer asynchronously and never writes a playlist. Context route-to-track previews are read-only until the generated suffix is explicitly sent to a player queue. |

`S` is the original source-track count. Last.fm track or artist evidence local to a transition `A -> B` is preferred; evidence from the complete original source artist pool is only a fallback. ListenBrainz remains later.

## Result and job UX

| Screen or action | Status | Current behavior |
| --- | --- | --- |
| Active preview | Partial | Real running job, retained only in LMS process memory; the page polls JSON-RPC status in place, keeps a manual full-result link, and exposes Cancel while the native process is still running. When the job reaches a terminal state, the page performs one anchored server render to show the full result. |
| Result | Partial | Real completed, failed, or cancelled job, lost on LMS restart. |
| Refresh result | Working | Automatically re-reads the selected in-memory job through `bettercallbliss job status` every 1.5 seconds while running without reloading or resetting scroll position. A manual full-result link remains available. |
| Cancel preview | Working for running previews | The current job and the running/recent previews panel can terminate the native optimizer process. No playlist or queue output is changed; persistence-phase cancellation and restart recovery remain future work. |
| Result summary | Working | Prominently reports running, Preview success/failure, and accept-time save/send success/failure, then shows selected strategy, objective, worst transition, and constraint validation. |
| Proposed order | Working | Shows every original track and its original position. |
| Additions and reasons | Working for difficult-transition improvements, Extend playlist, | Gap-improvement mode labels every added bridge with its endpoints, direct-gap percentile, and evidence tier/pool. Extend playlist labels each addition with its distance from the fixed full-source Adaptive reference and report source/addition/final counts. |
| Fixed-source extension diagnostics | Working | Reports best/mean/furthest fixed-source Adaptive relevance separately from final-route strategy, transition sum, worst transition, objective, and arc error. A collapsible acceptance section confirms exact target, every source track once, local additions, unique membership, and repeat-window compliance. |
| Transition summary | Partial | Aggregate reorder diagnostics are real; automatic and exact-count extension show one decision/reason per original gap, while a general per-leg drill-down remains open. |
| Warnings | Partial | Repeat validation, read-only safety, Last.fm provider fallback states, and a service-wide-error circuit breaker are real; a complete provider/cache dashboard remains open. |
| Running and recent previews | Partial | Extras shows running previews plus the most recent completed, failed, and cancelled previews retained in LMS memory. The current Preview status and the Running/Recent lists update in place from JSON-RPC polling; users can open retained jobs and cancel running previews. Durable history, search, and export are not connected. |
| Full report | Partial | In-memory artifact identity is shown; durable report storage and download are not connected. |
| Non-LMS Bliss-row audit | Working | The audit is now diagnostic rather than part of the normal workflow: Extras shows it only when the current inventory has excluded rows. The private JSON ledger retains current/resolved state, reason, row identity, metadata, and first/last-seen observations across LMS restarts. Existing case-variant duplicates are identified separately and include the related exact LMS identity. |
| Accept preview | Working | Completed previews expose the output target only after the result has been reviewed. Changing output fields does not rerun the optimizer, and failed accept attempts keep the same preview available for retry. |
| Create optimized copy | Working | Separate post-Preview action writes and verifies a new LMS playlist. Blank names preserve Unicode from the decoded source filename and choose the next free numbered suffix; explicit collisions fail visibly and safely. |
| Overwrite source | Working | Separate post-Preview action requires explicit confirmation, replaces the source playlist file and LMS catalog order, and attempts to restore the original file if publication fails. |
| Send to player queue | Working | Separate post-Preview action sends the generated order to a selected player with Replace queue, Replace upcoming tracks, Append to queue, or Play next behavior, and optional playback start. Same-player Replace upcoming tracks rechecks the live queue and trims already-played preview items when the snapshot is still recognizable. |
| Change options and rerun | Working for in-memory jobs | Polling, success, failure, and accept-action pages restore every normalized job value into the editor; users can adjust those values and start another Preview. Drafts do not survive an LMS restart. |
| Discard result | Not connected yet | Session results expire naturally on LMS restart. |

## Settings

The Extras editor initializes scoring and repeat fields from BlissMixer. The
submitted values belong to that job only and never update BlissMixer's global
preferences. The bundled optimizer supports Adaptive and Static routing. A
learned matrix is optional: Adaptive blends it when supplied and otherwise uses
variance weighting for multi-track contexts plus Static BlissMixer weights for
one-track contexts. Extended Isolation Forest remains disabled and labeled.

**Additional route-search attempts**, automatic bridge budget, automatic trigger percentile, and Last.fm guidance values supply defaults for new jobs. Bounded settings use the same slider-enhanced numeric input convention as BlissMixer where practical. Every value that affects optimization is copied into and may be overridden by the job. The following settings are persisted to establish their future contract but are labeled **not connected yet** on the settings page:

- ListenBrainz enablement;
- semantic cache freshness and stale-offline lifetime; and
- persistent report retention.

Last.fm is optional and uses LastMix's anonymous access. Its plugin-wide enable
enable switch is complemented by separate per-job track and artist guidance defaults.
Timeouts, provider errors, malformed responses, rate limits, and missing
Internet access degrade to local Bliss evidence rather than fail optimization.
ListenBrainz remains optional and is deliberately deferred.

## Safety boundary

Version `0.15.0` keeps Preview read-only. Completed previews are accepted through explicit post-Preview actions: create a verified copy, overwrite the source playlist with confirmation, or send the result to a player queue. Create optimized copy uses Lyrion's core M3U serializer, verifies the same-directory temporary file, exclusively claims the final path without overwrite semantics, copies the verified bytes, creates the LMS catalog object, and compares both catalog and final-file order with the optimizer result. It rejects an explicit existing name without touching it, automatically chooses a free numbered name only when the field was left blank, and removes only artifacts created by the failed attempt. Overwrite source verifies the generated M3U and attempts to restore the original file if publication fails. Queue output does not write a saved playlist; it resolves the preview to LMS URLs and applies the chosen player queue action. Same-player Replace upcoming tracks validates the live queue against the preview snapshot and trims the accepted result after the current item when playback has advanced predictably.

Automatic and exact-count extension additionally require the native source membership proofs, an unchanged database file identity during the job, exact source subsequence preservation, unique final membership, and successful read-only resolution of every proposed bridge to a local LMS track. The frozen LMS-local allowlist is required for plugin addition jobs and is applied before the native candidate search. It is bound to the exact guarded `bliss.db` identity; an invalid checksum, wrong schema, unknown row, database mismatch, or missing source membership fails the request. The later per-bridge resolution remains a separate fail-closed proof if LMS membership changes after inventory capture.

Extend playlist additionally requires an exact target match, unique final membership, every source ID exactly once, exactly `T - S` resolved additions for target/double-count requests, and selection details for every added Bliss row. Its native proof block must also affirm local-inventory membership and artist/album/track repeat compliance before the plugin accepts the result. Added tracks never enter the relevance anchor; they affect only complete-membership routing.

Running results refresh automatically and completed/failed optimization and accept actions are displayed in prominent banners with stable error codes. After a job starts, every polling, result, and accept-action page rebuilds the editor from that job's normalized options. Inactive numeric controls remain submitted as read-only values, so failures and successful review pages retain the exact settings for adjustment and rerun. After a successful preview, **Accept this preview** lets the user choose the output target without rerunning the optimizer.
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
