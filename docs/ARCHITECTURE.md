# Architecture boundary

The stable project identities selected at bootstrap are:

| Item | Identity |
| --- | --- |
| Display name | `Bliss 'Em All` |
| Perl namespace | `Plugins::BlissEmAll` |
| Plugin directory | `BlissEmAll` |
| LMS command prefix | `blissemall` |
| Plugin UUID | `5ff183ce-3d88-4aa1-8fa5-28fed965af76` |
| Extension icon | `plugins/BlissEmAll/html/images/blissemall_MTL_icon_timeline.png` |
| Native command | `bliss-playlist-optimizer` |

The Perl plugin owns user interaction, LMS object resolution, MusicBrainz IDs,
optional Last.fm/ListenBrainz adapters, frozen evidence creation, jobs,
logging, reports, and playlist writes. It invokes the native command with an
argument array and exchanges versioned JSON files.

The native command owns request validation, read-only Bliss database access,
route search, bridge selection, repeat-window enforcement, deterministic
verification, and result/progress JSON. It never performs network requests or
writes an LMS playlist.

The initial release uses one process per job. Compatibility is discovered with
`bliss-playlist-optimizer version --json`; absence or incompatibility disables
the feature without affecting BlissMixer.

Version `0.9.0` preserves that process boundary while avoiding repeated database
preparation. The plugin attaches the same `device:inode:size:mtime` identity it
already uses for post-job mutation detection and gives the native process a
plugin-owned `blissemall/library-cache` directory. A matching versioned cache
reuses the streamed database hash, successful integrity check, and decoded
usable-track library. A cold job reads all usable features and metadata with one
ordered SQLite query; a changed identity, checksum failure, incompatible cache,
or decode error is a safe miss and rebuild. The plugin still compares the live
database identity before resolving any added tracks, so cache reuse does not
weaken the existing fail-closed result boundary.

For connected addition jobs, the plugin also passes a conservative internal-gap
shortlist limit of 256. The native process reserves endpoint-local semantic
evidence before filling the remainder with a deterministic acoustic proxy that
uses the strict initial-gap dynamic two-leg Adaptive rank, including accepted
status, worst-leg percentile, and detour percentile. Shortlisting reduces the expensive
strict search surface; it does not select a bridge. Final decisions still use
the contextual two-leg Adaptive scorer and all semantic, repeat, membership,
and acoustic gates. Omitting the limit at the native contract keeps exhaustive
behavior for parity and diagnosis.

## First writable vertical slice

The connected milestone supports **Reorder only**, **Extend automatically**,
and **Add exactly N tracks** through Preview and explicit **Create optimized copy**.
Both addition modes support optimized source order or immutable preserved
source order; preserved jobs add only inside existing gaps in this slice.
It resolves saved playlists through LMS objects, initializes Adaptive and repeat
values from BlissMixer, accepts validated per-job overrides, writes a private
versioned request in the LMS cache, and runs the bundled ARM64 optimizer with an
argument array. The Extras web UI renders the job state, selected strategy,
objective, worst transition, repeat validation, and numbered proposed order.
The rich form lives under Extras because the generic Applications/OPML adapter
supports hierarchical choices and one search-style text prompt, but does not
carry a portable set of checkbox, dropdown, and numeric form controls. The
playlist job editor presents source ordering independently from additions.
Client-side relevance
rules disable automatic/exact-count inputs outside their modes and route-search
attempts under preserved order. The Perl validator independently rejects
preserved-order requests that cannot possibly change the playlist.
Playlist persistence is a separate post-Preview action. It resolves the result back to
LMS track objects, uses Lyrion's core M3U formatter, verifies the temporary
playlist, claims the final path with exclusive creation, copies the verified
bytes, creates the catalog object, and verifies catalog and final-file order.
Both addition modes invoke the native `bridge` command with a frozen empty semantic graph until optional providers
are connected. It validates native membership proofs, resolves opaque
`bliss-row-N` identities read-only against the unchanged `bliss.db`, maps
them to local LMS tracks including CUE entries, and freezes the resolved URLs
in the in-memory job before persistence. Exact-count uses the native bounded
search with one bridge per internal transition, rejects counts above `S - 1`,
and accepts only a feasible artifact containing exactly the requested number;
native infeasibility is surfaced as a failed Preview without a partial result.
Automatic names come from the decoded
local playlist filename rather than the potentially mojibaked catalog title and
select the next free numbered suffix. Explicit name collisions and publication
races fail closed; source playlist overwrite is not reachable.

The Extras icon is registered explicitly in the `icons` page-link category
with the same string key as the plugin link. Material intentionally maps
unrecognized Extras images to its generic extension glyph; the
`MTL_icon_timeline` filename marker invokes Material's supported monochrome
`timeline` glyph. Other skins and extension metadata use the actual packaged
transparent monochrome PNG.

The product architecture allows a future matrix-free Adaptive fallback, but the
currently bundled optimizer build returns `MATRIX_REQUIRED`. Version `0.9.0`
therefore treats the learned matrix as a required core capability and reports
its absence in System status. Making it optional requires an implemented and
tested native fallback; the plugin must not claim one based only on the design
intent. Semantic providers are outside the native process and remain optional
and failure-tolerant.

LMS ties `STDERR` to its logging adapter. Native jobs therefore follow LMS's
scanner pattern: open private output handles, temporarily untie `STDERR`, fork
with an argument array through `Proc::Background`, restore the tie immediately,
and poll without blocking the server event loop.

Every route and bridge job requests a structured native `performance` object.
Completion logs include wall time, native time, and database-cache state at
INFO. When `plugin.blissemall` debug logging is enabled, one additional line
reports each sanitized native stage and elapsed milliseconds. Job results and
stderr remain in the private job directory; no track paths are added to timing
logs.
