# Plugin package

This directory contains the installable `0.15.3` Better Call Bliss plugin package. It contributes **Better Call Bliss** under Extras and exposes playlist/track context shortcuts for supported controllers such as Material Skin. Lyrion's Applications/OPML adapter cannot expose a portable rich multi-field form, so the job editor uses the same classic-web mechanism as Virtual Library Creator.

The repository-level overview lives at [chrober/lms-better-call-bliss](https://github.com/chrober/lms-better-call-bliss/). User-facing playlist modes and per-job options are described in the [strategy guide](https://github.com/chrober/lms-better-call-bliss/blob/main/ALGORITHMS.md), and the current working/partial/planned UX boundary is tracked in [UX status](https://github.com/chrober/lms-better-call-bliss/blob/main/docs/UX_STATUS.md).

The connected saved-playlist path selects a real saved playlist and starts a native Preview using the selected addition purpose: no additions, difficult-transition improvements, or **Extend playlist** (exact additions, final track count, or double count). Difficult-transition improvements use each local gap as their similarity base. Extend playlist selects new members against the complete original source set as a fixed reference, so **Reach a final track count** also covers the former seed-list growth workflow. It can route the complete source-plus-addition set freely or preserve the source-track order and place additions around those anchors. The connected player-queue path snapshots the full queue, the current-plus-upcoming segment, or only upcoming tracks and optimizes that immutable snapshot. The connected track path, **Bliss me there...**, starts a saved-default native destination route in the background without opening the Extras page. Automatic chooses the shortest route that reaches its quality target; when that target cannot be met, it instead returns and reports the smoothest repeat-safe route within the configured intermediate-track budget. Exact requires its configured count. A successful job automatically appends only the route suffix after a live queue-tail check. Extend playlist keeps the full source playlist as its immutable relevance anchor. BlissMixer supplies defaults, but every job may override the mixing strategy, artist, album, and track repeat windows, context size, learned blend, route-search restart count, strategy-neutral Variation, and optional Last.fm similar-track and similar-artist guidance. Both Last.fm guidance controls default to 75%; they only rerank local, Bliss-qualified candidates. Setting an artist or album window to zero disables that constraint, allowing single-artist or single-album collections to be optimized.

The plugin delegates acoustic scoring, route search, bridge selection, and fixed-source extension membership selection to an installed `bliss-playlist-optimizer` binary. Better Call Bliss owns Lyrion identity capture, optional LastMix/Last.fm evidence collection, Preview polling, result validation, and playlist or player-queue persistence, including replacing only the upcoming part of an active queue. A learned matrix is optional: Adaptive blends it when available, and otherwise falls back to variance plus Static BlissMixer weights for one-track contexts.

Better Call Bliss explicitly loads its own strings.txt during startup so development deployments from Cache/Plugins expose localized Extras captions and Settings labels even when LMS does not include that directory in its automatic string scan.

Credit: lms-blissmixer already provides the **Create bliss mix** action for immediate Bliss-based mix generation from a selected track, artist, album, or genre. Better Call Bliss is intentionally a companion workflow, not a replacement for that feature: it adds auditable previews, per-job playlist and queue constraints, and explicit persistence choices around saved playlists and player queues.

The job editor labels ordering as **Source-track order**, asks for the **Additional tracks** purpose separately from **Chosen amount**, and labels Adaptive history as **Musical context window (previous tracks)**. It hides mode-specific sections when they are irrelevant, keeps their values for easy mode switching, uses BlissMixer-style slider-enhanced numeric inputs for bounded ranges where practical, places route-search attempts under Advanced, and rejects guaranteed no-op preserved combinations in both the page and server validator.

**Preserve source order and fill gaps** is connected for difficult-transition
improvements and Extend playlist. Every original track
remains an immutable anchor in its input order. Difficult-transition
improvements inspect source gaps and may add zero. Extend playlist uses the
same fixed-source-set membership selection as the native extension path, so exact additions,
final target count, and double-count requests are not capped by the number of
existing gaps. Preserve order with no possible addition is rejected as a
guaranteed no-op. The plugin verifies the native ordering-policy echo, exact
source order, final original subsequence, unique membership, and requested
count before a result can be persisted.

The package includes a 512x512 transparent monochrome route icon. Its filename
contains Material's `MTL_icon_timeline` marker, so the Extras renderer selects
the theme-colored monochrome `timeline` glyph instead of falling back to the
generic extension/puzzle icon. `Web.pm` registers the icon explicitly under
the same key as the Extras link.

Warning, error, success, and information banners force explicit high-contrast
foreground/background pairs on both their containers and every nested element,
including bold/list content that host themes would otherwise repaint. Notes and disabled hints follow the host
`--text-color` with reduced emphasis rather than using fixed gray text.

Difficult-transition improvement adds only candidates that pass the native contextual
trigger, acoustic-improvement, uniqueness, and repeat gates, up to the per-job
budget. Opaque Bliss row identities are validated, resolved read-only through
`bliss.db` to local LMS tracks immediately after Preview, and frozen as LMS
URLs. The result shows every addition and every transition decision. LastMix
track and artist evidence is optional and failure-tolerant; ListenBrainz remains later.

Variation is a per-job percentage downstream of the scoring strategy. Zero
keeps strict best-match membership, while higher values use reproducible
weighted sampling inside a bounded top acoustic pool. A blank seed generates a
new result on every run; an explicit generation seed reproduces the selection.
The Last.fm defaults mirror BlissMixer's enable switch and 1-100 artist
probability. Better Call Bliss queries every distinct artist from the complete
original playlist, prefers endpoint-local evidence, uses the complete set only
as fallback, and continues with Bliss when LastMix or Last.fm is unavailable.
Service-offline, temporarily-unavailable, and rate-limit errors stop the
remaining provider calls for that job instead of repeatedly hitting Last.fm.

Every addition job first snapshots current local LMS track identities and intersects them with usable `TracksV2` rows. The resulting checksum-protected allowlist is bound to the exact `bliss.db` file identity and applied natively before candidate shortlisting or scoring. Unmatched Bliss rows remain excluded even when their acoustic score would otherwise win. A persistent ledger at `<LMS cache>/bettercallbliss/non-lms-bliss-rows.json` records their paths, metadata, reasons, first/last-seen times, observation counts, and resolved/current state for review. The Extras page keeps this out of the normal workflow and shows the audit box only when the current inventory has excluded rows. Existing files are not automatically eligible: when a Bliss row differs from a unique LMS identity only by filename case, the audit records `filename_case_differs_from_lms_catalog` and the related LMS identity, preserving exact membership and preventing duplicate case-variant candidates.

Extend playlist accepts a per-job exact addition count, final track count, or double-count preset. It computes the requested final size and delegates membership selection to the native fixed-source extension request, so it can add more tracks than there are source gaps. Infeasible searches fail visibly and no partial result can be persisted.

Difficult-transition bridge improvements use a deterministic 256-track internal-gap
shortlist before strict bridge evaluation. This is an implementation-level
performance bound, not a musical scoring replacement or user-visible job
parameter. The proxy retains endpoint-local semantic candidates first and uses
the strict initial-gap dynamic two-leg Adaptive rank for the remainder,
including accepted status, worst-leg percentile, and detour percentile. The
evolving-state scorer and every semantic, repeat,
membership, and acoustic gate still make the final choice. Debug performance
output separates shortlisting from strict candidate scoring.

Running Preview status updates in place through the Better Call Bliss JSON-RPC job command, can be cancelled while the native optimizer is still active, and completed/failed/cancelled optimization plus accept actions are displayed in prominent banners with stable error codes. The plugin passes a job-local `progress.json` sidecar to `bliss-playlist-optimizer`; while the native process runs, the Running/Recent panel and live banner show the optimizer's current `msg`, stage, and progress counters when available, falling back to plugin-side phase labels otherwise. The full result is rendered once after the job reaches a terminal state rather than reloading the page every polling cycle. After a job starts, every polling, result, and accept-action page rebuilds the editor from that job's normalized options. Inactive numeric controls remain submitted as read-only values, so failures and successful review pages retain the exact settings for adjustment and rerun. The Extras page also shows running previews and the most recent completed, failed, or cancelled previews retained in LMS memory; this Running/Recent panel updates in place while polling. Durable history and export remain future work. After a successful preview, **Accept this preview** lets the user choose the output target without rerunning the optimizer. Create optimized copy writes through Lyrion's core M3U formatter, exclusively creates a new file, creates the LMS playlist object, and verifies both file and catalog order. Blank names are Unicode-safe and select the next available numbered copy; explicit collisions fail visibly. Overwrite source requires confirmation and replaces the source playlist. Send to player queue applies the selected queue action to the selected player; **Replace upcoming tracks** leaves the currently playing item untouched and swaps only the queue tail. When source and target are the same player, the plugin rechecks the live queue and trims already-played preview items if the snapshot is still recognizable.
The still-unconnected controls are explicitly marked **Not connected yet**: advanced strict gap bridge placement, add N bridge tracks per source transition, duration-based target/double presets, multi-track preserved gaps beyond the current UI slice, explicit opening/closing additions, persistence-phase cancellation, durable reports/history, ListenBrainz evidence, and Extended Isolation Forest routing. See [UX status](https://github.com/chrober/lms-better-call-bliss/blob/main/docs/UX_STATUS.md) for the exact working/partial/future feature matrix.
