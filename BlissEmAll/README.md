# Plugin package

This directory contains the installable `0.11.0` per-job UX shell. It contributes
**Bliss 'Em All** under Extras and retains informational playlist/track context
entries. Lyrion's Applications/OPML adapter cannot expose a portable rich
multi-field form, so the job editor uses the same classic-web mechanism as
Virtual Library Creator.

The connected paths select a real saved playlist and start a native
reorder-only, automatic-extension, exact-count, or exact-target **Grow from
these seeds** Preview. Seed growth keeps the full source playlist as its
immutable relevance anchor. BlissMixer supplies defaults, but every job may
override the artist, album, and track repeat windows, Adaptive seed count,
learned blend, and route-search restart count. Setting an artist or album window to zero
disables that constraint, allowing single-artist or single-album collections to
be optimized.

The job editor labels ordering as **Source-track order**, additions separately,
and Adaptive history as **Musical context window (previous tracks)**. Automatic
addition inputs are disabled when irrelevant, route-search attempts live under
Advanced and are disabled for preserved order, and guaranteed no-op preserved
combinations are rejected in both the page and server validator.

**Preserve source order and fill gaps** is connected for automatic and
exact-count additions. Every original track remains an immutable anchor in its
input order. This first UI slice permits at most one addition in each internal
gap and keeps opening/closing slots disabled. Preserve order with no possible
addition is rejected as a guaranteed no-op. The plugin verifies the native
ordering-policy echo, exact source order, final original subsequence, unique
membership, and requested count before a result can be persisted.

The package includes a 512x512 transparent monochrome route icon. Its filename
contains Material's `MTL_icon_timeline` marker, so the Extras renderer selects
the theme-colored monochrome `timeline` glyph instead of falling back to the
generic extension/puzzle icon. `Web.pm` registers the icon explicitly under
the same key as the Extras link.

Warning, error, success, and information banners force explicit high-contrast
foreground/background pairs on both their containers and every nested element,
including bold/list content that host themes would otherwise repaint. Notes and disabled hints follow the host
`--text-color` with reduced emphasis rather than using fixed gray text.

Automatic extension adds only candidates that pass the native contextual
trigger, acoustic-improvement, uniqueness, and repeat gates, up to the per-job
budget. Opaque Bliss row identities are validated, resolved read-only through
`bliss.db` to local LMS tracks immediately after Preview, and frozen as LMS
URLs. The result shows every addition and every transition decision. Optional
semantic providers are not connected in this slice, so it reports the honest
Bliss-only evidence mode.

Every addition job first snapshots current local LMS track identities and intersects them with usable `TracksV2` rows. The resulting checksum-protected allowlist is bound to the exact `bliss.db` file identity and applied natively before candidate shortlisting or scoring. Unmatched Bliss rows remain excluded even when their acoustic score would otherwise win. A persistent ledger at `<LMS cache>/blissemall/non-lms-bliss-rows.json` records their paths, metadata, reasons, first/last-seen times, observation counts, and resolved/current state for review; the Extras page shows the current count and file location after the first addition job. Existing files are not automatically eligible: when a Bliss row differs from a unique LMS identity only by filename case, the audit records `filename_case_differs_from_lms_catalog` and the related LMS identity, preserving exact membership and preventing duplicate case-variant candidates.

Exact-count extension accepts a per-job positive integer up to the number of
internal source transitions. It succeeds only when the native bounded search
returns exactly that many unique bridges with membership proofs; infeasible
searches fail visibly and no partial result can be persisted.

Both connected addition modes use a deterministic 256-track internal-gap
shortlist before strict bridge evaluation. This is an implementation-level
performance bound, not a musical scoring replacement or user-visible job
parameter. The proxy retains endpoint-local semantic candidates first and uses
the strict initial-gap dynamic two-leg Adaptive rank for the remainder,
including accepted status, worst-leg percentile, and detour percentile. The
evolving-state scorer and every semantic, repeat,
membership, and acoustic gate still make the final choice. Debug performance
output separates shortlisting from strict candidate scoring.

Running results refresh automatically and completed/failed optimization and
copy states are displayed in prominent banners with stable error codes. After
a job starts, every polling, result, and copy-action page rebuilds the editor
from that job's normalized options. Inactive numeric controls remain submitted
as read-only values, so failures and successful review pages retain the exact
settings for adjustment and rerun. After a successful preview, Create optimized
copy writes through Lyrion's core M3U
formatter, exclusively creates a new file, creates the LMS playlist object, and
verifies both file and catalog order. Blank names are Unicode-safe and select
the next available numbered copy; explicit collisions fail visibly. The source
is never changed. Overwrite source remains visibly unavailable.

All remaining extension modes and source overwrite are visibly marked **Not
connected yet**. See `docs/UX_STATUS.md` in the repository root for the exact
working/partial/future feature matrix.
