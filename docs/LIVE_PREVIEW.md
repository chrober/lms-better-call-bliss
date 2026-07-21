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

## Current UX boundary

The `0.2.0` plugin exposes the complete planned UX shell. Only **Optimize order
> Reorder only > Run preview** is executable. Ordering/extension alternatives,
numeric inputs, bridge discovery, semantic providers, cancellation, durable
history, report export, and playlist creation are each visibly marked **Not
connected yet**. Informational playlist and track context entries are also
registered, but do not start actions.

A Run action is terminal so OPML navigation cannot replay it; users return to
**Active previews** or **Recent results** for safe, read-only refreshes. See
[`UX_STATUS.md`](UX_STATUS.md) for the screen-by-screen feature matrix.

The full-shell deployment also established the piCorePlayer development path:
manual plugins belong beneath `<LMS cache>/Plugins`, while
`<LMS cache>/InstalledPlugins/Plugins` is extension-manager-owned and may purge
hand-copied folders during restart. The live `0.2.0` shell is therefore staged
at `Cache/Plugins/BlissEmAll` until the plugin ZIP and extension repository are
published.
