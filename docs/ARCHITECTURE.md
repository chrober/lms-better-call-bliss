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

## First vertical slice

The first live milestone supports only **Reorder only** and stops at Preview.
It resolves saved playlists through LMS objects, initializes Adaptive and repeat
values from BlissMixer, accepts validated per-job overrides, writes a private
versioned request in the LMS cache, and runs the bundled ARM64 optimizer with an
argument array. The Extras web UI renders the job state, selected strategy,
objective, worst transition, repeat validation, and numbered proposed order.
The rich form lives under Extras because the generic Applications/OPML adapter
supports hierarchical choices and one search-style text prompt, but does not
carry a portable set of checkbox, dropdown, and numeric form controls. Playlist
persistence remains disabled until this path is proven on a real server.

The product architecture allows a future matrix-free Adaptive fallback, but the
currently bundled optimizer build returns `MATRIX_REQUIRED`. Version `0.3.0`
therefore treats the learned matrix as a required core capability and reports
its absence in System status. Making it optional requires an implemented and
tested native fallback; the plugin must not claim one based only on the design
intent. Semantic providers are outside the native process and remain optional
and failure-tolerant.

LMS ties `STDERR` to its logging adapter. Native jobs therefore follow LMS's
scanner pattern: open private output handles, temporarily untie `STDERR`, fork
with an argument array through `Proc::Background`, restore the tie immediately,
and poll without blocking the server event loop.
