# Plugin package

This directory contains the installable `0.3.0` per-job UX shell. It contributes
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

The editor also captures whether a future accepted result should create an
optimized copy or overwrite the source. This release remains preview-only, so
neither choice writes a playlist yet.

All other modes and mutations are visibly marked **Not connected yet**. The
milestone deliberately disables playlist creation. See `docs/UX_STATUS.md` in
the repository root for the exact working/partial/future feature matrix.
