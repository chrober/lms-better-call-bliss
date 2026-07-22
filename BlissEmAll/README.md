# Plugin package

This directory contains the installable `0.5.0` per-job UX shell. It contributes
**Bliss 'Em All** under Extras and retains informational playlist/track context
entries. Lyrion's Applications/OPML adapter cannot expose a portable rich
multi-field form, so the job editor uses the same classic-web mechanism as
Virtual Library Creator.

The connected paths select a real saved playlist and start either a native
reorder-only or automatic-extension Preview. BlissMixer supplies defaults, but every job may override
the artist, album, and track repeat windows, Adaptive seed count, learned blend,
and route-search restart count. Setting an artist or album window to zero
disables that constraint, allowing single-artist or single-album collections to
be optimized.

Automatic extension adds only candidates that pass the native contextual
trigger, acoustic-improvement, uniqueness, and repeat gates, up to the per-job
budget. Opaque Bliss row identities are validated, resolved read-only through
`bliss.db` to local LMS tracks immediately after Preview, and frozen as LMS
URLs. The result shows every addition and every transition decision. Optional
semantic providers are not connected in this slice, so it reports the honest
Bliss-only evidence mode.

After a successful reorder preview, Create optimized copy writes through
Lyrion's core M3U formatter, atomically publishes a new file, creates the LMS
playlist object, and verifies both file and catalog order. The source is never
changed. Overwrite source remains visibly unavailable.

All other extension modes and source overwrite are visibly marked **Not
connected yet**. See `docs/UX_STATUS.md` in the repository root for the exact
working/partial/future feature matrix.
