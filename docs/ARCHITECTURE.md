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

