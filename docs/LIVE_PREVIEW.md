# Live preview milestone

The read-only vertical slice was exercised end to end on 2026-07-21 with LMS
9.1.1 on ARM64. The test used an anonymized nine-track saved playlist.

Verified path:

1. LMS discovered the plugin and registered **Bliss 'Em All** under
   Applications / My Apps.
2. System status reported BlissMixer, `bliss.db`, the learned matrix required
   by the current optimizer build,
   the native optimizer, and scanner state.
3. The review screen captured the server's real Adaptive configuration: three
   seed tracks, 20% learned blend, and artist/album/track look-back windows of
   5/10/100.
4. **Run preview** created a private request and launched the ARM64 optimizer
   asynchronously from the LMS process.
5. **Recent results** displayed a completed Adaptive route, objective 2.273,
   worst transition 0.299, satisfied repeat constraints, and all nine tracks in
   their proposed order.
6. The original saved playlist and its M3U file remained untouched.

The run also established runtime-specific integration rules now encoded in the
plugin: use LMS 9.1's multi-root `getAudioDirs()` API, emit real JSON booleans,
and untie LMS's `STDERR` trap while creating a redirected child process.
Native filesystem paths are compared while still in locale bytes, then decoded
exactly once with `utf8decode_locale()` before JSON serialization. This keeps
non-ASCII filenames identical to their `bliss.db` identities. CUE identities
also receive the same `.CUE_TRACK.<number>` suffix used by BlissMixer.

Native failures are decoded into a stable code and message. The UI identifies
the affected LMS track when available, while `server.log` receives an ERROR
record containing job ID, code, exit status, elapsed time, and message. DEBUG
adds the captured scoring/repeat configuration without logging a full playlist.
The structured stderr artifact is authoritative even when LMS has already
reaped the child and `Proc::Background` can no longer recover its true exit
status. Result JSON is attempted first; an empty/invalid result then falls back
to the native error envelope regardless of the observed exit code.

For a route-search failure, the plugin also checks simple hard-constraint
capacity. If one artist or album occurs too often to fit its configured window,
the UI reports the occurrence count, required separators, available separators,
and that fixed-set reordering cannot repair the conflict. It never silently
weakens inherited repeat windows.

## Per-job Extras editor verification

Version `0.3.0` was deployed and exercised on the same ARM64 server on
2026-07-22. LMS registered the rich editor under Extras and no longer returned
Bliss 'Em All in the Applications query.

An anonymized 13-track, single-artist playlist completed successfully after the
job set artist and album look-back windows to zero. The same submitted job also
overrode Adaptive context tracks to 2, learned blend to 33%, track look-back to
100, and route-search restarts to 12. Inspection of the private
`request.json` confirmed those exact values; the completed native result used
Adaptive routing with objective 4.924 and worst transition 0.548.

The form captured the requested create-copy output name while remaining
read-only. No playlist writer is reachable in this milestone. This proves that
BlissMixer preferences are defaults rather than immutable execution settings,
and that disabling an impossible artist constraint is an explicit job choice
rather than an automatic weakening by the optimizer.

A second preview of the same playlist selected **Overwrite source** with different per-job
values. The result page retained that choice and displayed **Not executed**;
the INFO start record included the effective algorithm, seed/blend, repeat
windows, restarts, and output mode. Its request artifact separately retained
the BlissMixer defaults (seed 3, learned 20%, artist window 5) and the effective
job values (seed 4, learned 25%, artist window 0).

## Current UX boundary

The original `0.2.0` live run used Applications/My Apps. Source version `0.3.0`
moves the editor to Extras after verifying that the generic Applications/OPML
adapter cannot carry the required portable multi-field form. **Optimize order >
Reorder only > Run read-only preview** remains executable. Adaptive parameters,
repeat windows, search restarts, and output disposition are now job fields;
BlissMixer values are defaults only. Version `0.5.0` additionally connects
automatic Bliss-only bridge discovery. Preserve-order and exact-count
alternatives, static or forest routing, semantic providers, cancellation,
durable history, report export, and source overwrite remain visibly marked
**Not connected yet**.

## Create-copy persistence verification

Version `0.4.0` connected **Create optimized copy** as a separate action after
a completed Preview and was exercised on the same ARM64 LMS server on
2026-07-22. A 13-track single-artist playlist was previewed with artist and
album look-back disabled for that job. Creating its optimized copy produced a
new LMS playlist with 13 tracks and a new catalog ID.

Independent JSON-RPC verification mapped the optimizer's selected source IDs
back to URLs and confirmed that the resulting LMS catalog order matched exactly.
The published M3U contained 13 `#EXTURL:file:///` records, 13 `#EXTINF`
records, and the corresponding decoded local paths in Lyrion's native format.
The source URL-list SHA-256 remained
`12931afcd693afc1ea4f20c34171ede78db85677c3760b30128a25a58f0bdeb8`
before and after creation.

A second completed Preview intentionally reused the same output name. Creation
failed with stable code `OUTPUT_EXISTS`; the existing output and source were
unchanged and no `.blissemall-*` temporary file remained. The server log
correlated the Creating and CreatedAndVerified stages with the preview job ID.
The persistence path does not launch a scanner: like Lyrion's own playlist-save
command it updates the playlist object directly, then additionally verifies
catalog and file order.

## Automatic extension verification

Version `0.5.0` connected **Extend automatically** on 2026-07-22. A
seven-track anonymized playlist was submitted with Adaptive seed limit 3,
learned blend 20%, artist/album/track windows 5/10/100, zero route restarts, a
one-track bridge budget, and a 0th-percentile trigger. The ARM64 native
`bridge` command completed in about 20 seconds over 63,822 usable Bliss rows.

The Preview selected one bridge through the explicit
`bliss-only-empty-graph` fallback. The plugin validated the final-sequence
proofs, resolved the opaque row to a local LMS track, rendered the eight-track
order with **Added bridge**, and showed all original-gap decisions. No optional
network provider was contacted.

The explicit Create action produced a new eight-track saved playlist. Independent
comparison of the native `final_sequence`, request source-ID-to-URL mapping,
and LMS JSON-RPC output reported exact order equality. Exactly one output URL
was outside the seven source URLs. The M3U contained eight
`#EXTURL:file:///` and eight `#EXTINF` records, no private temporary file
remained, and the source still contained seven tracks with URL-list SHA-256
`e85f20d212a21823d60cf6d733ba7e288a076dd2065692e93b66bd26b77b2b6a`.
Server-log lifecycle records captured the effective extension mode, budget,
trigger, repeat/scoring parameters, final and added counts, evidence mode,
Creating, and CreatedAndVerified stages under one job ID.

The deployment also exposed an important development rule: a rollback copy
must not remain beneath `Cache/Plugins`, because Lyrion scans it as another
plugin source and can compile its older templates under the live namespace.
Rollback copies now live beneath `Cache/BlissEmAll-backups`, outside the
scanned plugin root.

A submitted preview polls automatically and retains a manual refresh link using
its session job ID. See
[`UX_STATUS.md`](UX_STATUS.md) for the screen-by-screen feature matrix.

## UX feedback and Unicode-safe naming verification

Version `0.5.1` was exercised through the actual Extras HTTP workflow on
2026-07-22 with an anonymized 13-track, single-artist playlist whose filename
ends in an emoji flag. The LMS catalog title exposed mojibaked bytes, while its
file URL retained the correct UTF-8 filename. The plugin now decodes that file
URL for display and automatic naming; the proposed optimized-copy name retained
both regional-indicator code points.

The submitted running page contained the automatic 1.5-second poll and visible
running banner. An intentionally impossible artist repeat window completed with
a prominent `ROUTE_SEARCH_FAILED` banner, capacity guidance, and an explicit
statement that no playlist changed. A second valid run displayed the Preview
success banner without requiring log inspection.

An explicit create attempt then reused the source playlist name. The page
displayed `Copy not created - OUTPUT_EXISTS` and stated that the source and
existing copy were unchanged. The sole matching M3U retained SHA-256
`02c9abebedd751d8182615c09db554eea3a9c1cedcc961823f24c1ab1824f333`
before and after the attempt. Final-path publication now uses exclusive
creation, so it has no overwrite-capable rename. Blank-name jobs instead choose
the next available suffix such as `(2)`.

The full-shell deployment also established the piCorePlayer development path:
manual plugins belong beneath `<LMS cache>/Plugins`, while
`<LMS cache>/InstalledPlugins/Plugins` is extension-manager-owned and may purge
hand-copied folders during restart. The development shell is therefore staged
at `Cache/Plugins/BlissEmAll` until the plugin ZIP and extension repository are
published.
