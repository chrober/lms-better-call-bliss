# Automatic Playlist Improvement Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans and test-driven development; retain progress in this checklist.

**Goal:** Replace the two separate addition purposes with one workflow whose spacing and smoothing goals can be enabled independently.  
**Architecture:** The optimizer owns one versioned combined mode and the two sequential search phases, sharing the addition budget and preserving the original anchor identities. Better Call Bliss owns controls, request normalization, capability negotiation and result validation.  
**Tech Stack:** Rust, JSON schemas, Perl, LMS templates and JavaScript.  
**Spec:** `docs/superpowers/specs/2026-10-29-automatic-playlist-improvement-design.md`.  

## Global constraints

- Respect repeat windows, unique membership, source order policy and candidate restrictions; previews remain read-only.
- Spacing gets first use of the common additions budget; smoothing examines actual post-spacing adjacent tracks.
- An already-valid source is not an error. An unachievable mandatory spacing result is an error.
- Map previously saved automatic and spacing choices to the equivalent individual goals.
- Preserve established logs; introduce separate diagnostics for new behavior when necessary.

## Review focus

- A spacing insertion changes both endpoints and context of downstream smoothing gaps.
- Source identities and spacing/addition reasons survive native artifact serialization and host resolution.
- Disabled goals, zero remaining budget and an unchanged valid route remain well-defined.
- Repeat, candidate identity and membership checks apply across both phases, not per phase in isolation.
- Old native binaries and previously saved settings do not silently run different behavior.

## Tasks

### Native contract and two-phase search

**Files:** `src/main.rs`, `src/preview.rs`, `schemas/optimizer-request-v1.schema.json`, `schemas/bridge-analysis-artifact-v1.schema.json`, synthetic fixtures and Rust tests in `bliss-playlist-optimizer`.  
**Interface:** a new capability-gated `automatic_improvement` bridge mode with boolean `satisfy_repeat_windows` and `smooth_transitions`, one `max_added_tracks`, and `trigger_percentile` when smoothing is enabled. Its selection artifact identifies original tracks and spacing versus smoothing additions, includes phase counts and final validation proofs.  

- [ ] Add failing request-schema and native tests for each goal alone, both together, no repeat conflict, disabled goals, budget exhaustion, and invalid constraints.
- [ ] Add tests covering a difficult transition adjacent to an inserted spacing track, duplicate exclusion and whole-route repeat validation.
- [ ] Implement the validated contract, capability probe, source-order handling and shared-budget two-phase planner. Reuse native candidate ranking and global spacing machinery; regenerate gap evidence for the actual intermediate route.
- [ ] Verify `cargo fmt --check`, focused tests and the repository's complete locked CI test suite.

### Better Call Bliss controls and native integration

**Files:** `BetterCallBliss/JobOptions.pm`, `RequestBuilder.pm`, `BlissCompatibility.pm`, `Plugin.pm`, `Web.pm`, `BridgeResolver.pm`, `Jobs.pm`, `LogDiagnostics.pm`, the Extras template and related tests.  
**Interface:** one `automatic_improvement` purpose with independent repeat-spacing and transition-smoothing booleans; map legacy `automatic` and `satisfy_constraints` to equivalent goals.  

- [ ] Add failing tests for option defaults, both independent controls, legacy mappings, request JSON types and unsupported optimizer capability.
- [ ] Add failing artifact-validation tests for spacing, smoothing and mixed results, including source order, unique tracks, full-route repeats, shared budget and reasons.
- [ ] Implement UI state restoration, conditional controls, capability checks, request generation, progress, safe artifact resolution and reporting. Preserve existing output behavior and established log lines.
- [ ] Run the focused Perl and UI tests, followed by the complete supported plugin test suite.

### Documentation and end-to-end verification

**Files:** `ALGORITHMS.md`, root and shipped READMEs and `docs/UX_STATUS.md`.  

- [ ] Update user-facing mode descriptions, applicable options and examples to reflect the implemented behavior and native capability requirement.
- [ ] Exercise synthetic end-to-end previews for each goal combination and the failure cases; inspect the complete diff for stale labels, schema mismatches and unrelated changes.
- [ ] Report exact tests and limitations; do not deploy, publish or change a live playlist without explicit authorization.
