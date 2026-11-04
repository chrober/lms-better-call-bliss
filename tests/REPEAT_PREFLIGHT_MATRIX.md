# Repeat-window preflight scenario matrix

These checks are necessary conditions, not a guarantee that a candidate library
contains a feasible route. Disabled repeat windows impose no corresponding bound.
The host checks before candidate-library capture; the optimizer retains an
independent check before loading its database.

| Scenario | Early check | Feasible / impossible coverage |
| --- | --- | --- |
| Reorder without additions | Host checks per-artist and per-album capacity; other combinations may still need search. | `request_json_types.t` and optimizer route tests |
| Automatic improvement, preserved order and spacing enabled | Host calculates the minimum spacing for fixed anchors against the maximum budget. | `request_json_types.t`, `automatic_improvement.t`, optimizer repair tests |
| Automatic improvement, optimized order | Host checks an order-independent minimum; the chosen order is checked later. | `request_json_types.t`, `optimized_repeat_window_repair_routes_sources_before_adding_spacing` |
| Automatic improvement, smoothing only | Host rejects source conflicts that would require spacing; smoothing alone is not a repeat repair. | `automatic_improvement.t`, `request_json_types.t` |
| Extension by track count | Host checks the source identities against the final track-count capacity. | `request_json_types.t` |
| Extension by duration | Host checks duration bounds; a source-only repeat capacity check applies when no additions are needed. Membership and its repeat feasibility require candidate data. | `duration_membership.rs`, optimizer duration tests |
| Legacy exact-count / target-count bridge requests | With preserved order, host and optimizer reject anchor conflicts that cannot be solved even at the maximum number of bridges per gap; optimized order is not rejected based on the original sequence. | `round_trip_repeat_preflight.t`, `legacy_exact_count_preflight_uses_the_maximum_per_gap`, `request_json_types.t` |
| Fixed N tracks per gap, preserved order | Host and optimizer check artist, album and track identity at the projected anchor distances. | `round_trip_repeat_preflight.t`, `fixed_gap_preflight_respects_reordering_and_checks_track_repeats` |
| Fixed N tracks per gap, optimized order | Neither preflight rejects based on the original ordering; source routing uses windows scaled to projected gap distances, with a final route proof. | `fixed_gap_preflight_respects_reordering_and_checks_track_repeats`, `optimized_fixed_gap_can_separate_original_repeat_with_a_bridge` |
| One-way destination, track or album | Host and optimizer compare all destination tracks with earlier history and the start anchor; the ordered album itself is immutable. | `round_trip_repeat_preflight.t`, `destination_album_preflight_accounts_for_all_immutable_tracks` |
| Destination and queue rejoin | Host and optimizer calculate separate outward and return lower bounds with a shared budget. The original queue anchors are not required to satisfy each other. | `round_trip_repeat_preflight.t`, `round_trip_preflight_accounts_for_both_repeat_boundaries`, `round_trip_keeps_existing_queue_anchors_even_when_album_repeats` |
| Generated bridges around an album | Final generated-track checks include the entire destination block, without imposing repeat windows inside that block. | `destination_bridge_tracks_must_respect_all_album_anchors` |

The native tests are in `bliss-playlist-optimizer/src/main.rs` and
`bliss-playlist-optimizer/src/preview.rs`. Passing preflight does not mean the
bounded search will find a solution: candidate eligibility, uniqueness,
acoustic quality, repeat interactions and search limits remain relevant.
