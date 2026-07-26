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
automatic Bliss-only bridge discovery, and version `0.6.0` connects exact-count
Bliss-only bridge discovery. Preserve-order and the remaining extension
presets, static or forest routing, semantic providers, cancellation,
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

## Clarified controls and extension icon verification

Version `0.5.2` was deployed on 2026-07-23. The live status command reported
`ready=1`, no compatibility problems, and
`ux_contract=extras-job-editor-v5`. The rendered Extras page exposed
**Source-track order**, **Additional tracks**, **Musical context window
(previous tracks)**, and the Advanced **Additional route-search attempts**
control together with the directional bridge explanation.

The page contains relevance logic for automatic-addition fields, preserved
order, route attempts, and guaranteed no-op combinations. A handcrafted
Preserve source order + no-additions POST was rejected with the specific
server-side message before native execution. A normal two-track reorder Preview
then completed successfully while the irrelevant automatic-addition inputs were
omitted, proving default handling remained intact.

The extension metadata now declares
`plugins/BlissEmAll/html/images/blissemall.png`. HTTP verification returned
`image/png` at 512x512. The transparent ARGB asset remains legible at 32x32
and depicts four charcoal source-track nodes, an amber bridge node inserted into
the route, and a forward arrow. It was generated with the built-in image tool
on a flat chroma background, processed with the installed image-skill
background-removal helper, and alpha/dimension validated before packaging.

## Accessible banners and Material Extras icon verification

Version `0.5.3` was deployed on 2026-07-23. The live status command reported
`ready=1`, no compatibility problems, and
`ux_contract=extras-job-editor-v6`.

The status banners no longer inherit Material's light foreground color while
using a light banner background. Warning, error, success, and information
states now declare their own foreground/background pairs. Their WCAG contrast
ratios are respectively 12.25:1, 12.00:1, 9.43:1, and 10.40:1. Secondary note
and disabled text uses the active skin's `--text-color` with reduced emphasis.
The live rendered page returned HTTP 200 and contained the explicit warning and
error foreground rules.

The earlier PNG was correctly present in the server's Extras payload, but
Material's client deliberately maps any unrecognized Extras image to its
generic `extension` glyph. The replacement is a transparent monochrome
512x512 route asset named
`blissemall_MTL_icon_timeline.png`. Both `install.xml` and `Web.pm`
register that path. Material's supported marker parser resolves it to the
theme-colored monochrome `timeline` glyph, while other consumers can load the
actual PNG.

Live `material-skin extras` verification returned:

```text
id=PLUGIN_BLISSEMALL_NAME
icon=plugins/BlissEmAll/html/images/blissemall_MTL_icon_timeline.png
material_glyph=timeline
```

The new icon URL returned HTTP 200 as `image/png`. The generated asset was
processed with the installed image-skill chroma-removal helper, one-pixel edge
contraction, high-quality 512x512 resampling, and alpha/fringe validation.

## Exact-count extension verification

Version `0.6.0` was deployed and exercised through the live Extras HTTP
workflow on 2026-07-26. The status command reported `ready=1`, zero compatibility
problems, `ux_contract=extras-job-editor-v7`, and exact extension in its working
mode. The page rendered the enabled **Add exactly N tracks** choice, its
mode-specific numeric editor, all-or-nothing explanation, selected-playlist
limit, and calculated final size.

A read-only Preview used an anonymized 13-track single-artist playlist, requested
one addition, and explicitly disabled artist and album look-back for that job.
The native `bridge` request captured `mode=exact_count`,
`additional_track_count=1`, `max_tracks_per_gap=1`, disabled opening/closing
slots, and the submitted repeat windows. It completed with Adaptive-arc routing,
one bridge, 14 final tracks, true unique-membership and original-subsequence
proofs, a maximum of one feasible addition found, and a structural upper bound
of 12. The result page reported **Added exactly 1 track**, the bounded-search
capacity, the Bliss-only evidence mode, the final order, and addition reasons.

The Preview did not invoke persistence: querying saved playlists found no entry
with the submitted output name. A separate two-track boundary request asked for
two additions and was rejected before native execution with a concise maximum
of one additional track. The banner contained no internal Perl path. Native
contract tests independently cover the second failure boundary: a completed
exact-count analysis that cannot find `N` returns an infeasibility proof with a
null final sequence, and the plugin converts that proof into a failed Preview
rather than accepting a partial result.

A final two-track smoke run requested one addition and rendered the corrected
singular success text with three final tracks. Its explicit Create action
reported **Created and verified**. An independent LMS query found all two source
URLs exactly once, one additional URL, three unique URLs, and three total tracks
in the saved copy. The test then deleted only that newly created playlist by its
returned LMS ID through the core `playlists delete` command and confirmed that
no matching saved playlist remained.

## Prepared-library cache and timing verification

Version `0.7.0` was deployed on 2026-07-26 from plugin commit `12f00e4` with
optimizer commit `ec8b6a5`. The ARM64 binary SHA-256 is
`fde138541697ca21cf32a64f132a8ed0adbc882c78d94feae6cef9052166f64d`.
After restart, `blissemall status` returned `ready=1`, zero compatibility
problems, and the unchanged `extras-job-editor-v7` UX contract.

The cold path now streams the database hash, runs `quick_check`, and obtains all
63,822 usable feature/metadata rows with one ordered SQLite query instead of one
metadata query per track. It writes a checksum-protected 16.9 MiB cache bound to
the plugin's `device:inode:size:mtime` database identity. Warm jobs reuse the
database hash, integrity result, and decoded library; identity mismatch, cache
checksum failure, format mismatch, or decode failure rebuilds it.

An anonymized 13-track reorder-only Preview was executed twice with identical
Adaptive and repeat settings. The proposed route and objective were identical:

| Measurement | Cold cache | Warm cache |
| --- | ---: | ---: |
| Native total | 5,183 ms | 2,065 ms |
| Plugin wall time | 5,510 ms | 2,357 ms |
| Database cache | miss | hit |
| Route search | 248 ms | 239 ms |

The cold-only stages were database hashing (749 ms), open/integrity checking
(288 ms), bulk library decoding (1,926 ms), and cache writing (883 ms). The warm
path spent 664 ms decoding the cache. Remaining fixed per-process costs were
request/schema validation (805 ms), semantic artifact/schema validation
(279 ms), and source resolution (41 ms).

A bounded two-track, one-gap exact-count Preview then completed with one added
track in 3,888 ms native and 4,013 ms wall time on a warm cache. Its measured
bridge stages were candidate preparation (449 ms), gap candidate scoring
(693 ms), and exact bridge selection/revalidation (688 ms). This validates the
timing contract and also shows that exhaustive bridge work remains the dominant
scaling problem.

For comparison, an eight-addition Preview over an anonymized 13-track
single-artist collection was stopped after more than four minutes and roughly
12 accumulated CPU-minutes. It remained read-only, the plugin reported a failed
Preview, and the UI confirmed that no playlist was changed. The next performance
gate is therefore a measured high-recall acoustic shortlist before strict
contextual reranking, plus user-visible cancellation/resource bounds. Merely
adding Rayon workers or caching preparation cannot make multi-gap exact search
interactive.

## Strict-rank bridge shortlist verification

Version `0.8.0` was deployed on 2026-07-26 from plugin commit `d55e1c7` with
optimizer commit `b6d3d10`. The ARM64 binary SHA-256 is
`f2c3f8a743072625820ad8f3208f6595d5ee529cdb0232a50819af6c284252a6`.
Both optimizer workflows passed, and the restarted server reported `ready=1`,
zero compatibility problems, and `extras-job-editor-v7`.

Addition requests now declare an internal-gap shortlist limit of 256. Each gap
first uses the existing strict dynamic two-leg Adaptive rank over the frozen
eligible pool, while endpoint-local semantic candidates are reserved. Only the
256 retained candidates enter repeated evolving-route scoring. Existing native
requests that omit the limit remain exhaustive.

The two-track, one-gap exact-count oracle had 63,820 eligible candidates. The
shortlisted result selected `bliss-row-49`, identical to the previous exhaustive
result, and added exactly one track. It completed in 3,174 ms native versus
3,888 ms exhaustive, an 18.4% reduction. Relevant stages were:

| Stage | Exhaustive | Shortlisted |
| --- | ---: | ---: |
| Candidate preparation | 449 ms | 458 ms |
| Initial gap ranking / shortlisting | 693 ms | 613 ms |
| Repeated shortlisted gap scoring | included above | 2 ms |
| Exact selection and final diagnostics | 688 ms | 2 ms |

Two earlier proxy designs were rejected by this live oracle before this gate
was accepted. A learned candidate-to-right proxy chose `bliss-row-983`; an exact
local-objective proxy chose `bliss-row-764`. Neither matched the production
rank contract, which prioritizes accepted status, semantic tier, worst-leg
percentile, and detour percentile before bounded route comparison. Reusing that
strict rank restored the exhaustive winner and is covered by deterministic
worker-count and end-to-end parity tests.

The formerly runaway 13-track, exact-eight request completed native analysis in
21,142 ms with a feasible 21-track sequence and exactly eight proposed bridges.
It previously exceeded four minutes and was stopped. The shortened run spent
8,113 ms ranking and shortlisting all 12 original gaps, 37 ms in initial
shortlisted rescoring, and 10,064 ms in bounded exact selection.

The plugin then failed closed with `BRIDGE_TRACK_NOT_IN_LMS` because selected
candidate `bliss-row-21660` did not resolve to a current local LMS track. No
playlist was created or changed. This is a separate membership boundary rather
than a performance failure: the optimizer currently enumerates usable Bliss
rows, while LMS membership is validated only after native selection. The next
correctness gate is a frozen, database-bound local-LMS candidate inventory (or
an equivalent exclusion/retry contract) so non-LMS Bliss rows cannot enter the
search. User-visible cancellation and bounded resource policy remain required
before enabling the larger extension presets.
