# Plugin package

This directory contains the installable `0.4.0` per-job UX shell. It contributes
**Bliss 'Em All** under Extras and retains informational playlist/track context
entries. Lyrion's Applications/OPML adapter cannot expose a portable rich
multi-field form, so the job editor uses the same classic-web mechanism as
Virtual Library Creator.

The connected path selects a real saved playlist and starts a native,
reorder-only preview. BlissMixer supplies defaults, but every job may override
the artist, album, and track repeat windows, Adaptive seed count, learned blend,
and route-search restart count. Setting an artist or album window to zero
disables that constraint, allowing single-artist or single-album collections to
be optimized.

After a successful reorder preview, Create optimized copy writes through
Lyrion's core M3U formatter, atomically publishes a new file, creates the LMS
playlist object, and verifies both file and catalog order. The source is never
changed. Overwrite source remains visibly unavailable.

All extension modes and source overwrite are visibly marked **Not connected
yet**. See `docs/UX_STATUS.md` in the repository root for the exact
working/partial/future feature matrix.
