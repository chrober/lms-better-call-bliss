# Live preview milestone

The read-only vertical slice was exercised end to end on 2026-07-21 with LMS
9.1.1 on ARM64. The test used an anonymized nine-track saved playlist.

Verified path:

1. LMS discovered the plugin and registered **Bliss 'Em All** under
   Applications / My Apps.
2. System status reported BlissMixer, `bliss.db`, the optional learned matrix,
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

## Current UX boundary

Only **Reorder only** is executable. **Preserve order and fill gaps** is shown
as the next mode, while playlist creation is visibly disabled. A Run action is
terminal so that OPML navigation cannot replay it; users return to **Active
previews** or **Recent results** for safe, read-only refreshes.
