# Architecture boundary

The stable project identities selected at bootstrap are:

| Item | Identity |
| --- | --- |
| Display name | `Bliss 'Em All` |
| Perl namespace | `Plugins::BlissEmAll` |
| Plugin directory | `BlissEmAll` |
| LMS command prefix | `blissemall` |
| Plugin UUID | `5ff183ce-3d88-4aa1-8fa5-28fed965af76` |
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

## First writable vertical slice

The connected live milestone supports **Reorder only** and **Extend
automatically** through Preview and explicit **Create optimized copy**.
It resolves saved playlists through LMS objects, initializes Adaptive and repeat
values from BlissMixer, accepts validated per-job overrides, writes a private
versioned request in the LMS cache, and runs the bundled ARM64 optimizer with an
argument array. The Extras web UI renders the job state, selected strategy,
objective, worst transition, repeat validation, and numbered proposed order.
The rich form lives under Extras because the generic Applications/OPML adapter
supports hierarchical choices and one search-style text prompt, but does not
carry a portable set of checkbox, dropdown, and numeric form controls. Playlist
persistence is a separate post-Preview action. It resolves the result back to
LMS track objects, uses Lyrion's core M3U formatter, verifies the temporary
playlist, claims the final path with exclusive creation, copies the verified
bytes, creates the catalog object, and verifies catalog and final-file order.
Automatic extension invokes the native `bridge` command with a frozen empty semantic graph until optional providers
are connected. It validates native membership proofs, resolves opaque
`bliss-row-N` identities read-only against the unchanged `bliss.db`, maps
them to local LMS tracks including CUE entries, and freezes the resolved URLs
in the in-memory job before persistence. Automatic names come from the decoded
local playlist filename rather than the potentially mojibaked catalog title and
select the next free numbered suffix. Explicit name collisions and publication
races fail closed; source playlist overwrite is not reachable.

The product architecture allows a future matrix-free Adaptive fallback, but the
currently bundled optimizer build returns `MATRIX_REQUIRED`. Version `0.5.0`
therefore treats the learned matrix as a required core capability and reports
its absence in System status. Making it optional requires an implemented and
tested native fallback; the plugin must not claim one based only on the design
intent. Semantic providers are outside the native process and remain optional
and failure-tolerant.

LMS ties `STDERR` to its logging adapter. Native jobs therefore follow LMS's
scanner pattern: open private output handles, temporarily untie `STDERR`, fork
with an argument array through `Proc::Background`, restore the tie immediately,
and poll without blocking the server event loop.
