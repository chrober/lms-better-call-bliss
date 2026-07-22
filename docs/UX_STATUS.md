# UX contract and implementation status

This document describes the complete intended **Bliss 'Em All** interaction
model and the exact boundary of the current `0.4.0` UX shell. The shell is
deliberately broader than the backend so the remaining implementation can be
connected without redesigning the user journey.

The UI uses three explicit states:

- **Working**: the action executes real plugin/native behavior.
- **Partial**: useful data is real, but lifecycle or persistence is incomplete.
- **Not connected yet**: the planned control or screen is visible, but cannot
  start a job or mutate data.

Items marked **Not connected yet** are informational. They must not silently
fall through to the working reorder-only mode.

## Entry points

| Entry point | Status | Current behavior |
| --- | --- | --- |
| Extras > Bliss 'Em All | Working | Opens the rich per-job editor and result area. |
| Applications / My Apps > Bliss 'Em All | Removed | The OPML adapter cannot provide the required portable multi-field form. |
| Saved-playlist context > Bliss 'Em All... | Partial | Visible informational shortcut; directs the user to Extras. |
| Track context > Bliss me there... | Not connected yet | Describes the planned route-to-track capability; starts no job. |
| Full EN/DE menu localization | Not connected yet | The Extras shell is English-first; settings labels have EN/DE strings. |

## Optimization wizard

| Step or option | Status | Contract |
| --- | --- | --- |
| Select saved playlist | Working | Lists LMS saved playlists with at least two tracks. |
| Optimize order | Working for Reorder only | Original tracks may move. |
| Preserve order and fill gaps | Not connected yet | Original sequence remains fixed; additions may occupy gaps only. |
| Reorder only | Working | Uses every original track exactly once and inserts none; a reviewed result can be saved as a new copy. |
| Extend automatically | Not connected yet | Adds up to the configured budget only where a bridge materially helps. |
| Add exactly N tracks | Not connected yet | Adds exactly a user-entered number of unique eligible tracks. |
| One bridge per transition | Not connected yet | Adds one track in each of the `S - 1` original transitions, yielding `2S - 1` tracks. |
| Target length | Not connected yet | Adds tracks until the exact total `T >= S` is reached. |
| Double length | Not connected yet | Adds exactly `S` tracks, yielding `2S` tracks. |
| Numeric editor for N/T | Not connected yet | Will validate values before review. |
| Adaptive context tracks | Working, per job | Initialized from BlissMixer and passed to this job's native request. |
| Learned-matrix blend | Working, per job | Validated as 0-100 and passed to this job's native request. |
| Artist/album/track look-back | Working, per job | Initialized from BlissMixer; zero disables the corresponding constraint. |
| Route-search restarts | Working, per job | Validated as 0-500 and passed to this job's native request. |
| Static weighted / random-forest strategy | Not connected yet | Visible but disabled because native route currently accepts Adaptive only. |
| Review | Working for reorder-only | The submitted form and result retain the job-specific values. |
| Run preview | Working for reorder-only | Launches the native optimizer asynchronously and never writes a playlist. |

`S` is the original source-track count. Future bridge discovery will use local
Bliss evidence first. Similar-artist evidence local to transition `A -> B` will
be preferred; evidence from the full source artist pool is only a fallback.

## Result and job UX

| Screen or action | Status | Current behavior |
| --- | --- | --- |
| Active preview | Partial | Real running job, retained only in LMS process memory. |
| Result | Partial | Real completed/failed job, lost on LMS restart. |
| Refresh result | Working | Re-reads the selected in-memory job. |
| Cancel preview | Not connected yet | No cancellable native-process handle is exposed. |
| Result summary | Working | Shows selected strategy, objective, worst transition, and constraint validation. |
| Proposed order | Working | Shows every original track and its original position. |
| Additions and reasons | Shell only | Correctly reports no additions for Reorder only; future bridge provenance is not connected. |
| Transition summary | Partial | Aggregate objective/worst transition are real; per-leg drill-down is not connected. |
| Warnings | Partial | Repeat validation and read-only safety are real; provider warnings await providers. |
| Full report | Partial | In-memory artifact identity is shown; durable report storage and download are not connected. |
| Create optimized copy | Working | Separate post-Preview action writes and verifies a new LMS playlist; name collisions fail closed. |
| Overwrite source | Not connected yet | Captured for UX continuity but never mutates the source. |
| Change options and rerun | Not connected yet | Draft restoration is not implemented. |
| Discard result | Not connected yet | Session results expire naturally on LMS restart. |

## Settings

The Extras editor initializes scoring and repeat fields from BlissMixer. The
submitted values belong to that job only and never update BlissMixer's global
preferences. The current bundled optimizer supports only Adaptive routing and
requires a learned matrix; unsupported strategies are disabled and labeled.

**Route search restarts** changes execution and **Normal output suffix** supplies
the default create-copy name. The following settings are persisted to establish
their future contract but are labeled
**not connected yet** on the settings page:

- extended output suffix;
- automatic bridge budget;
- Last.fm and ListenBrainz enablement;
- semantic cache freshness and stale-offline lifetime; and
- persistent report retention.

Last.fm and ListenBrainz remain optional. Once connected, timeouts, provider
errors, malformed responses, rate limits, and missing Internet access must
degrade to cached or local Bliss evidence rather than fail optimization.

## Safety boundary

Version `0.4.0` keeps Preview read-only and permits only an explicit,
post-Preview **Create optimized copy** mutation. The writer uses Lyrion's core
M3U serializer, verifies the same-directory temporary file, atomically renames
it, creates the LMS catalog object, and compares both catalog and final-file
order with the optimizer result. It rejects an existing name without touching
it and removes only artifacts created by the failed attempt. Lyrion's playlist
object is updated directly, so this workflow does not depend on a library scan.
Source overwrite, extension modes, and every other shell-only action remain
unreachable.

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
