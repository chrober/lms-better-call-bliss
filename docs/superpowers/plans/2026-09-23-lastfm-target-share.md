# Last.fm Target-Share Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Better Call Bliss's two Last.fm percentages behave as best-effort target shares of selected additions, using a widened but still Bliss-derived candidate pool.

**Architecture:** The optimizer receives host-neutral per-channel selection targets beside existing guidance weights. A shared target-aware ranking component keeps compact route/extension selection state and calibrates preference only among a 10× Bliss-qualified pool. Better Call Bliss removes the redundant master checkbox: both channel values at zero skip Last.fm acquisition.

**Tech Stack:** Rust 2024, `bliss-playlist-guidance-spi`, JSON Schema, Perl/Lyrion templates, Perl tests, Rust contract and unit tests.

**Spec:** `docs/superpowers/specs/2026-09-19-guidance-spi-migration-design.md`

## Global Constraints

- Last.fm and play-count guidance remain advisory; local-library, genre, uniqueness, repeat, and acoustic admission rules remain hard constraints.
- `0` disables an individual Last.fm channel; a Last.fm provider is not started when both channel targets are zero.
- Any provider failure is neutral and retains Bliss-only planning.
- Candidate expansion is bounded and must remain practical for 200,000-track libraries.
- Results must remain deterministic for a fixed request, seed, and provider artifact.
- Do not add provider-specific conditionals to planner implementations.

## Review Focus

- A `75%` target with insufficient endorsed candidates must report the attainable share, without selecting non-Bliss candidates.
- Track and artist support on one candidate must count toward both targets, without double-selecting that candidate.
- `0%` for one channel must suppress that channel while retaining the other channel and LastMix acquisition where necessary.
- A Last.fm-provider timeout or malformed response must produce a valid Bliss-only result and target diagnostics marked unavailable.
- A fixed request must produce the same selected IDs and target diagnostics with one Rayon worker and with the normal worker count.

### Task 1: Add host-neutral channel target contracts

**Files:**
- Modify: `D:/LMS/bliss-playlist-guidance-spi/src/lib.rs`
- Modify: `D:/LMS/bliss-playlist-guidance-spi/schemas/guidance-request-v2.schema.json`
- Modify: `D:/LMS/bliss-playlist-optimizer/schemas/optimizer-request-v1.schema.json`
- Modify: `D:/LMS/bliss-playlist-optimizer/src/main.rs`
- Test: `D:/LMS/bliss-playlist-guidance-spi/tests/protocol.rs`
- Test: `D:/LMS/bliss-playlist-optimizer/tests/contracts.rs`

**Interfaces:**
- Consumes: existing `(provider_id, channel, weight)` guidance policy entries.
- Produces: optional `target_percent: u8` per policy entry and a versioned result diagnostic with requested/available/achieved counts.

- [ ] **Step 1: Write the failing protocol test**

```rust
#[test]
fn policy_target_percent_round_trips_and_rejects_values_above_100() {
    let entry: GuidancePolicyEntry = serde_json::from_str(
        r#"{\"provider_id\":\"lastfm-guidance\",\"channel\":\"lastfm_track\",\"weight\":1.0,\"target_percent\":75}"#,
    ).unwrap();
    assert_eq!(entry.target_percent, Some(75));
    assert!(serde_json::from_str::<GuidancePolicyEntry>(
        r#"{\"provider_id\":\"lastfm-guidance\",\"channel\":\"lastfm_track\",\"weight\":1.0,\"target_percent\":101}"#,
    ).is_err());
}
```

- [ ] **Step 2: Run the protocol test and verify it fails because `target_percent` does not exist**

Run: `cargo test -p bliss-playlist-guidance-spi policy_target_percent_round_trips_and_rejects_values_above_100`

- [ ] **Step 3: Add the optional bounded field to the shared Rust type, schema, optimizer request deserialization, and contract fixture**

```rust
#[serde(default, skip_serializing_if = "Option::is_none")]
pub target_percent: Option<u8>,
```

The field is optional for existing non-target guidance such as signed play-count preference. Reject values greater than 100 through the shared schema and deserializer validation.

- [ ] **Step 4: Re-run the focused protocol and optimizer contract tests**

Run: `cargo test -p bliss-playlist-guidance-spi policy_target_percent_round_trips_and_rejects_values_above_100; cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml --test contracts`

- [ ] **Step 5: Commit the contract change**

```powershell
git -C D:/LMS/bliss-playlist-guidance-spi add src/lib.rs schemas/guidance-request-v2.schema.json tests/protocol.rs
git -C D:/LMS/bliss-playlist-guidance-spi commit -m "feat: add guidance channel target percentages"
git -C D:/LMS/bliss-playlist-optimizer add schemas/optimizer-request-v1.schema.json src/main.rs tests/contracts.rs
git -C D:/LMS/bliss-playlist-optimizer commit -m "feat: accept guidance channel targets"
```

### Task 2: Implement one shared target-aware Bliss-first selector

**Files:**
- Modify: `D:/LMS/bliss-playlist-optimizer/src/guidance.rs`
- Modify: `D:/LMS/bliss-playlist-optimizer/src/preview.rs`
- Modify: `D:/LMS/bliss-playlist-optimizer/src/main.rs`
- Test: `D:/LMS/bliss-playlist-optimizer/src/guidance.rs`
- Test: `D:/LMS/bliss-playlist-optimizer/src/preview.rs`

**Interfaces:**
- Consumes: Bliss-ranked candidate IDs, aggregate provider contributions, configured channel targets, and compact selected-member counts.
- Produces: deterministic candidate order plus per-channel requested, available, selected, and achieved diagnostics.

- [ ] **Step 1: Write failing unit tests for channel target behavior**

```rust
#[test]
fn target_uses_supported_candidate_inside_widened_bliss_pool() {
    let order = rank_target_aware_candidates(
        &[1, 2, 3, 4],
        &support([(1, vec![]), (2, vec!["lastfm_track"]), (3, vec![]), (4, vec![])]),
        &targets([("lastfm_track", 75)]),
        SelectionProgress::default(),
        4,
    );
    assert_eq!(order[0], 2);
}

#[test]
fn zero_target_is_neutral() {
    let order = rank_target_aware_candidates(/* supported candidate at rank two, target zero */);
    assert_eq!(order, vec![1, 2, 3, 4]);
}
```

Also add tests for overlapping track/artist support, unavailable support, stable tie breaks, and a candidate outside the supplied pool never being returned.

- [ ] **Step 2: Run the focused tests and verify they fail because the shared selector is absent**

Run: `cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml target_uses_supported_candidate_inside_widened_bliss_pool`

- [ ] **Step 3: Add `TargetSelectionState` and `rank_target_aware_candidates` in `guidance.rs`**

The selector must derive the remaining desired count from `target_percent`, already selected additions, and the active planner's remaining addition budget. It must calculate a deterministic per-channel multiplier from available support in the supplied pool, add it to existing aggregate guidance only for supported candidates, and use Bliss rank then stable candidate ID as tie breakers. A selected candidate updates every supported channel once.

- [ ] **Step 4: Route both existing shared boundaries through it**

Replace the fixed-source extension's `maximum_shift` block and `preview::rank_guided_shortlist`'s fixed `MAX_GUIDANCE_SHIFT` policy. Both boundaries must request a pool size of `max(required_additions, required_additions * 10)` when any channel target is non-zero, bounded by the configured shortlist limit. Preserve the existing no-guidance and play-count-only behavior.

- [ ] **Step 5: Run the focused unit tests and full optimizer suite**

Run: `cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml; cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml --test contracts`

- [ ] **Step 6: Commit the shared selection implementation**

```powershell
git -C D:/LMS/bliss-playlist-optimizer add src/guidance.rs src/preview.rs src/main.rs
git -C D:/LMS/bliss-playlist-optimizer commit -m "feat: honor guidance channel target shares"
```

### Task 3: Make Better Call Bliss request and display target shares

**Files:**
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/JobOptions.pm`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/RequestBuilder.pm`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/Jobs.pm`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/Web.pm`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/HTML/EN/plugins/BetterCallBliss/index.html`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/HTML/EN/plugins/BetterCallBliss/settings/bettercallbliss.html`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/strings.txt`
- Test: `D:/LMS/lms-better-call-bliss/tests/request_builder.t`
- Test: `D:/LMS/lms-better-call-bliss/tests/web.t`

**Interfaces:**
- Consumes: per-job target values `lastfm_track_guidance_percent` and `lastfm_artist_guidance_percent`.
- Produces: `target_percent` in matching `guidance_policy` entries, no Last.fm artifact/addon if both are zero, and requested/available/achieved target diagnostics in the preview.

- [ ] **Step 1: Write failing Perl tests for request construction**

```perl
is($request->{guidance_policy}[0]{target_percent}, 75,
   'track target is sent to the optimizer');
ok(!grep({ $_->{provider_id} eq 'lastfm-guidance' } @{$zero_request->{guidance_addons}}),
   'both zero targets skip the Last.fm provider');
```

- [ ] **Step 2: Run the focused Perl test and verify it fails**

Run: `prove -lv tests/request_builder.t`

- [ ] **Step 3: Make Last.fm activation derive from either target value**

Remove `lastfm_enabled` from the form state and request normalization. Add `target_percent` to the corresponding policy entries while retaining their channel-specific signal weights as internal calibration. Skip LastMix collection and omit the provider configuration only when both normalized targets are zero or LastMix is unavailable.

- [ ] **Step 4: Update the Extras and Settings controls**

Remove the master checkbox. Keep two `0..100` Material slider inputs. Rename the labels and descriptions to “Similar-track target share (%)” and “Similar-artist target share (%)”; explain that they are best effort among Bliss-qualified, local, repeat-safe choices and that `0` disables that source. Update job-result text to show requested and achieved counts/shares instead of only a generic “guidance applied” count.

- [ ] **Step 5: Run focused Perl tests and the plugin suite**

Run: `prove -lr tests`

- [ ] **Step 6: Commit the plugin behavior and UI change**

```powershell
git -C D:/LMS/lms-better-call-bliss add BetterCallBliss tests
git -C D:/LMS/lms-better-call-bliss commit -m "feat: make Last.fm guidance target based"
```

### Task 4: End-to-end regression, documentation, and release preparation

**Files:**
- Modify: `D:/LMS/lms-better-call-bliss/ALGORITHMS.md`
- Modify: `D:/LMS/lms-better-call-bliss/docs/GUIDANCE_DATA_FLOW.md`
- Modify: `D:/LMS/bliss-playlist-optimizer/README.md`
- Test: `D:/LMS/bliss-playlist-optimizer/tests/contracts.rs`
- Test: `D:/LMS/lms-better-call-bliss/tests/request_builder.t`

- [ ] **Step 1: Add an end-to-end fixture with a Bliss-qualified Last.fm-supported candidate**

The fixture must prove a 75% track target changes at least one final selected addition relative to `0%`, retains deterministic selected IDs across two runs, and reports the achieved target. Add a companion fixture where all endorsed candidates are outside the Bliss-qualified widened pool and assert no non-Bliss candidate is selected.

- [ ] **Step 2: Run fixture, contracts, and plugin suites**

Run: `cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml; cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml --test contracts; prove -lr tests`

- [ ] **Step 3: Update product documentation**

Document the 10× Bliss-derived pool, best-effort target semantics, overlapping channel support, `0%` behavior, constraints that can prevent a target, and per-result achieved-share reporting. Do not imply Last.fm can add an acoustically inadmissible candidate.

- [ ] **Step 4: Verify clean diffs, then commit documentation**

Run: `git -C D:/LMS/bliss-playlist-optimizer diff --check; git -C D:/LMS/lms-better-call-bliss diff --check`

```powershell
git -C D:/LMS/bliss-playlist-optimizer add README.md tests
git -C D:/LMS/bliss-playlist-optimizer commit -m "docs: explain guidance target selection"
git -C D:/LMS/lms-better-call-bliss add ALGORITHMS.md docs/GUIDANCE_DATA_FLOW.md
git -C D:/LMS/lms-better-call-bliss commit -m "docs: explain Last.fm target shares"
```

