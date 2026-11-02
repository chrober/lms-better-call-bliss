# Target-duration playlist extension

**Goal:** Extend a source playlist to an independently bounded duration range while keeping Bliss similarity, repeat constraints and explicit preview acceptance.

**Architecture:** Better Call Bliss captures the target, percentage tolerances and Lyrion track durations in job-local inputs; the optimizer selects and routes fixed-source-relevant additions within the requested inclusive duration range. Both sides validate the result. Duration-based selection is a negotiated optimizer capability, not a guessed final track count.

**Constraints:** Default tolerance is 10% in each direction. If the source duration is inside the range, add no tracks; if it exceeds the maximum or a source duration is missing, fail clearly. Never return an out-of-range success. Maintain existing options, ordering semantics, provider behavior, the 500-track ceiling, and read-only preview. Remove the planned double-duration option.

## Work

- [x] Specify and test numeric input normalization, duration-bound rounding, empty/missing durations, and the no-addition case in the host.
- [x] Extend the trusted inventory and native request/result contracts with validated duration data and explicit capability discovery; test stale-cache compatibility and missing candidate durations.
- [x] Test and implement bounded duration-aware membership selection, repeat-safe routing and informative infeasibility; test alternatives where a greedy selection overshoots but a feasible combination exists.
- [x] Add the Extend playlist controls and restore/present job parameters and duration results; remove the two obsolete top-level placeholders.
- [x] Add request/result and regression tests for both source-order modes, target boundaries, no additions, missing data and repeat constraints. Update product documentation. Existing fixed-source guidance and variation paths are reused.
- [x] Run the relevant local test suites and report unavailable environment-dependent checks. The Pi and real Material/Lyrion UI remain unverified.

## Current implementation notes

- The host normalizes target minutes and independent tolerances, checks optimizer capability, and independently validates the returned duration against Lyrion track durations.
- The native optimizer uses a bounded membership search followed by repeat-safe routing. Exhausting the search is not a mathematical proof that no valid playlist exists.
- Candidate durations are captured from Lyrion's numeric `secs`; the inventory format revision causes an on-demand rebuild of an older cache, not advance rebuilding of every virtual library.
- This implementation has not been deployed or verified with a real Lyrion UI on the Pi.
