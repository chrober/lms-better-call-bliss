# Guidance SPI v2 Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Better Call Bliss's direct Last.fm and full-library play-count ranking paths with deterministic, provider-backed guidance that keeps Bliss as the acoustic authority.

**Architecture:** Better Call Bliss continues to collect and resolve Last.fm relations through LastMix, then supplies a frozen artifact to `bliss-guidance-lastfm`. It supplies a frozen eligible identity artifact and trusted Lyrion `persist.db` descriptor to `bliss-guidance-playcounts`; that provider reads only bounded candidate values during scoring, against one job-scoped SQLite snapshot. The optimizer owns provider lifecycle, shared shortlist-ranking boundaries, bounded aggregation, and result provenance.

**Tech Stack:** Rust 2021, Serde/JSONL, `rusqlite`, Rayon, SQLite/WAL, Perl/Lyrion plugin APIs, LastMix, JSON Schema, `Test::More`, Cargo tests.

**Spec:** `docs/superpowers/specs/2026-09-19-guidance-spi-migration-design.md`

## Global Constraints

- Use a breaking SPI v2; retain no compatibility shim or production dual path on migration branches.
- Bliss alone enforces acoustic distance, membership, virtual-library/genre filters, route feasibility, uniqueness, and repeat windows.
- Last.fm remains LastMix-backed and artifact-backed in this migration; direct Rust networking is out of scope.
- Play counts are read only by `bliss-guidance-playcounts`, never by Better Call Bliss or the optimizer.
- Trust executable paths, SQLite paths, resource descriptors, and provider policy only from plugin-owned configuration; never from LMS form data.
- Use Lyrion's standard `tracks_persistent.playcount` for this migration; Alternative Play Count is future work.
- Use `rusqlite` read-only access, `PRAGMA query_only=ON`, finite busy timeouts, bounded `urlmd5` batches, and no SQLite `immutable=1` flag.
- Normalize play counts against the frozen selected candidate library, treating absent counts as zero and equal counts with an average-rank percentile.
- Reuse one provider process per job; JSONL score payloads contain bounded shortlists only.
- Parallelize only independent CPU-bound work where profiling proves a benefit; preserve byte-stable order and results across Rayon worker counts.
- Do not duplicate decoded Bliss feature vectors or materialize a full-library play-count JSON/object map in a provider.
- Provider failures, timeouts, bad artifacts, schema mismatch, locked database, and no matches are neutral; hard constraints remain intact.

## Review Focus

- A valid virtual-library candidate with no `tracks_persistent` row must receive the same zero-count percentile as an explicit zero, not be silently dropped.
- Two equal play counts in different score batches must yield the same score and tie behavior as they would in one batch.
- A provider must never return an ID not present in the optimizer's current shortlist; the host must discard such output and record a failure.
- A Last.fm artifact hash or play-count identity artifact hash change after preparation must neutralize only that provider, not abort the playlist job.
- A live LMS update during a route must not change play-count scores after the provider's snapshot begins, and cancellation must release that snapshot.

---

## Repository and file map

| Repository | Files | Responsibility |
| --- | --- | --- |
| `bliss-playlist-guidance-spi` | `src/lib.rs`, `schemas/guidance-addon-spi-v2.schema.json`, `SPI.md`, `README.md` | Versioned typed protocol for artifact/resource preparation and bounded scores. |
| `bliss-guidance-lastfm` | `src/main.rs`, `README.md` | Adapt the existing artifact-backed Last.fm provider to SPI v2. |
| `bliss-guidance-playcounts` | `Cargo.toml`, `src/main.rs`, `README.md` | Read-only SQLite snapshot, streaming percentile distribution, and bounded candidate scoring. |
| `bliss-playlist-optimizer` | `src/guidance.rs`, `src/main.rs`, `src/preview.rs`, `src/semantic.rs`, request/result schemas, `tests/contracts.rs` | Provider host, trusted request validation, shared guided ranking, removal of direct semantic/play-count paths. |
| `lms-better-call-bliss` | `BetterCallBliss/CandidateInventory.pm`, `RequestBuilder.pm`, `Jobs.pm`, tests, packaging docs | Frozen candidate identities with `urlmd5`, LastMix artifact preparation, trusted provider registry, migration wiring, and deletion of the legacy play-count export. |

## Branch layout

- Create `feature/guidance-spi-v2` in `bliss-playlist-guidance-spi`.
- Create `feature/guidance-spi-v2` in both provider repositories.
- Continue the optimizer work on `feature/guidance-addons`, or rename it to `feature/guidance-spi-migration` before the first migration commit so the branch name matches the design.
- Create `feature/guidance-spi-migration` in `lms-better-call-bliss` from the current `main` after preserving the edited design and this plan.
- Do not merge or publish any component until its consumer uses the pinned commit containing SPI v2.

### Task 1: Publish the SPI v2 contract

**Files:**
- Modify: `D:/LMS/bliss-playlist-guidance-spi/src/lib.rs`
- Create: `D:/LMS/bliss-playlist-guidance-spi/schemas/guidance-addon-spi-v2.schema.json`
- Modify: `D:/LMS/bliss-playlist-guidance-spi/SPI.md`
- Modify: `D:/LMS/bliss-playlist-guidance-spi/README.md`

**Interfaces:**
- Produces `SPI_VERSION: u16 = 2` and `PROTOCOL_NAME: "bliss-playlist-optimizer-guidance-jsonl-v2"`.
- Produces `ArtifactDescriptor { kind, path, sha256 }` and `ResourceDescriptor { kind, path, access }`.
- Produces `GuidanceRequest::Prepare { job_id, options, artifacts, resources, anchors }`; it intentionally has no full candidate inventory.
- Produces `Candidate { candidate_id, lms_urlmd5, database_file, title, artist, album, recording_mbid, artist_mbids }` for bounded `score` batches.

- [ ] **Step 1: Write failing protocol round-trip tests**

Add tests that decode a v2 `prepare` containing one `resolved-lastfm-evidence-v1` artifact and a separate `lms-persist-sqlite-v1` resource, and a `score` candidate containing `lms_urlmd5`.

```rust
assert!(matches!(decoded, GuidanceRequest::Prepare {
    artifacts, resources, ..
} if artifacts.len() == 1 && resources.len() == 1));
assert_eq!(candidate.lms_urlmd5.as_deref(), Some("aabbcc"));
```

- [ ] **Step 2: Run the SPI tests to verify the current contract fails them**

Run: `cargo test --manifest-path D:/LMS/bliss-playlist-guidance-spi/Cargo.toml`

Expected: the new test does not compile because v1 has no descriptors or `lms_urlmd5`.

- [ ] **Step 3: Implement the v2 types and schema**

Use explicit types rather than unstructured `serde_json::Value` for shared descriptors:

```rust
pub struct ArtifactDescriptor { pub kind: String, pub path: String, pub sha256: String }
pub struct ResourceDescriptor { pub kind: String, pub path: String, pub access: ResourceAccess }
pub enum ResourceAccess { ReadOnly }
```

Keep provider-specific options as `Value`, reject wrong SPI versions, and document that `Prepare` never carries a decoded Bliss inventory or an unbounded candidate list.

- [ ] **Step 4: Run protocol and schema tests**

Run: `cargo test --manifest-path D:/LMS/bliss-playlist-guidance-spi/Cargo.toml`

Expected: all unit tests pass; the JSONL examples in `SPI.md` match schema v2 exactly.

- [ ] **Step 5: Commit the isolated SPI change**

```powershell
git -C D:/LMS/bliss-playlist-guidance-spi add src/lib.rs schemas/guidance-addon-spi-v2.schema.json SPI.md README.md
git -C D:/LMS/bliss-playlist-guidance-spi commit -m "feat: define guidance SPI v2 resources"
```

### Task 2: Convert the Last.fm provider to artifact-backed SPI v2

**Files:**
- Modify: `D:/LMS/bliss-guidance-lastfm/Cargo.toml`
- Modify: `D:/LMS/bliss-guidance-lastfm/src/main.rs`
- Modify: `D:/LMS/bliss-guidance-lastfm/README.md`

**Interfaces:**
- Consumes Task 1's `ArtifactDescriptor` and v2 `Candidate`.
- Produces only `lastfm_track` and `lastfm_artist` signals for IDs in the supplied score batch.
- Reads the verified `resolved-lastfm-evidence-v1` path once during `prepare`; it does not contact Last.fm.

- [ ] **Step 1: Write failing tests for artifact selection and bounded scoring**

Cover a `prepare` with the right artifact kind/hash descriptor, an unknown artifact kind, and a score batch where one candidate is resolved and one is not.

```rust
assert_eq!(signals.iter().map(|s| &s.candidate_id).collect::<Vec<_>>(), vec!["in-batch"]);
assert!(prepare(&wrong_artifact_descriptor).is_err());
```

- [ ] **Step 2: Run provider tests to verify they fail under SPI v1**

Run: `cargo test --manifest-path D:/LMS/bliss-guidance-lastfm/Cargo.toml`

Expected: compilation failures from the v1 `Prepare` shape.

- [ ] **Step 3: Implement v2 preparation without candidate snapshots**

Select the one `resolved-lastfm-evidence-v1` artifact descriptor, verify its SHA-256 before decoding, and index resolved evidence by source anchor and candidate ID. Preserve the current independent track and artist signal channels and concise rationale.

- [ ] **Step 4: Verify Last.fm provider behavior**

Run: `cargo test --manifest-path D:/LMS/bliss-guidance-lastfm/Cargo.toml`

Expected: artifact mismatch, missing evidence, and unmatched candidates return an error or empty signals as specified; no network dependency exists.

- [ ] **Step 5: Commit and record the SPI pin**

```powershell
git -C D:/LMS/bliss-guidance-lastfm add Cargo.toml Cargo.lock src/main.rs README.md
git -C D:/LMS/bliss-guidance-lastfm commit -m "feat: consume Last.fm artifacts through guidance SPI v2"
```

### Task 3: Implement direct SQLite play-count guidance

**Files:**
- Modify: `D:/LMS/bliss-guidance-playcounts/Cargo.toml`
- Modify: `D:/LMS/bliss-guidance-playcounts/src/main.rs`
- Modify: `D:/LMS/bliss-guidance-playcounts/README.md`

**Interfaces:**
- Consumes `eligible-candidate-identities-v1` artifact records `{ candidate_id, lms_urlmd5 }` and a trusted `lms-persist-sqlite-v1` resource.
- Produces `playcount` signals in `[-1, 1]`, where `-1` is the least-played eligible percentile and `+1` is the most-played.
- Uses one read-only SQLite snapshot and a bounded `HashMap<String, u64>` cache only for scored `urlmd5` values.

- [ ] **Step 1: Add failing SQLite fixture tests**

Create a temporary SQLite file with `tracks_persistent(urlmd5 TEXT PRIMARY KEY, playcount INTEGER)`, an identity JSON fixture containing three eligible IDs, and tests for zero/absent count handling, average-rank ties, batch consistency, missing schema, and an update after preparation.

```rust
assert_eq!(score("zero"), -1.0);
assert_eq!(score("missing"), -1.0);
assert_eq!(score("same-count-a"), score("same-count-b"));
assert_eq!(before_update, after_external_update);
```

- [ ] **Step 2: Run provider tests to verify the artifact-only provider cannot pass**

Run: `cargo test --manifest-path D:/LMS/bliss-guidance-playcounts/Cargo.toml`

Expected: tests fail because v1 accepts only `artifact_path` and does not open SQLite.

- [ ] **Step 3: Add read-only SQLite access and bounded distribution construction**

Add `rusqlite` with a portable bundled SQLite build. Open with `SQLITE_OPEN_READ_ONLY`, issue `PRAGMA query_only=ON`, set a finite busy timeout, begin a read transaction, validate `tracks_persistent` and required columns, then process the identity artifact in chunks of at most 900 URLMD5 values.

```rust
let rows = statement.query_map(params_from_iter(batch), |row| {
    Ok((row.get::<_, String>(0)?, row.get::<_, Option<u64>>(1)?))
})?;
```

Build a frequency histogram from all eligible values, including absent values as zero. Use the average rank among equal values to produce the stable percentile; do not retain an all-track `urlmd5 → count` map.

- [ ] **Step 4: Implement bounded score-time lookup and diagnostics**

At `score`, deduplicate only that request's `lms_urlmd5` values, query uncached values in bounded batches from the open snapshot, cache them, and return signals only for IDs in the request. Include snapshot identity, known/zero count, distribution size, query batches, cache hits, and elapsed time in diagnostics.

- [ ] **Step 5: Run provider tests and static checks**

Run: `cargo test --manifest-path D:/LMS/bliss-guidance-playcounts/Cargo.toml`

Expected: all fixture tests pass, including stable results after a concurrent external write and neutral schema failure.

- [ ] **Step 6: Commit the provider migration**

```powershell
git -C D:/LMS/bliss-guidance-playcounts add Cargo.toml Cargo.lock src/main.rs README.md
git -C D:/LMS/bliss-guidance-playcounts commit -m "feat: query Lyrion play counts through SQLite guidance"
```

### Task 4: Implement the optimizer's SPI v2 host and bounded signal validation

**Files:**
- Modify: `D:/LMS/bliss-playlist-optimizer/Cargo.toml`
- Modify: `D:/LMS/bliss-playlist-optimizer/src/guidance.rs`
- Modify: `D:/LMS/bliss-playlist-optimizer/src/main.rs`
- Modify: `D:/LMS/bliss-playlist-optimizer/tests/contracts.rs`

**Interfaces:**
- Consumes v2 SPI types and trusted request `guidance_addons` configuration.
- Produces `GuidanceBatch { adjustment_by_candidate: BTreeMap<usize, f64>, observed, applied, diagnostics }`.
- Calls `GuidanceHost::prepare(job_id, ProviderPreparation)` once and `GuidanceHost::score(context, shortlist)` only at shared ranking boundaries.

- [ ] **Step 1: Add failing host tests with a JSONL fixture provider**

Use a tiny fixture executable that records `prepare` and `score` lines. Assert that prepare contains descriptors and anchors but no `candidates`, that score contains only the supplied shortlist, and that an out-of-batch returned ID is rejected and disables only that provider.

```rust
assert!(prepared["artifacts"].is_array());
assert!(prepared.get("candidates").is_none());
assert_eq!(scored["candidates"].as_array().unwrap().len(), 2);
assert_eq!(host.score(...).signals.len(), 0);
```

- [ ] **Step 2: Run optimizer contract tests to verify the current v1 host fails**

Run: `cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml --test contracts`

Expected: fixture assertions fail because v1 sends the full candidate inventory during prepare.

- [ ] **Step 3: Refactor `GuidanceHost` around v2 preparation**

Replace `Session::prepare(job_id, candidates, anchors)` with a provider-specific `ProviderPreparation` built from verified artifact/resource descriptors and anchors. Preserve finite timeouts, process cleanup, and neutral failure behavior. Add `close` handling before `Drop` kills a healthy child.

- [ ] **Step 4: Add deterministic aggregation and provider telemetry**

Use stable candidate IDs and sorted channel/provider order. Aggregate only valid signals:

```rust
let adjustment = signals.iter()
    .map(|s| channel_weight(&s.channel) * s.score * s.confidence)
    .sum::<f64>()
    .clamp(-GUIDANCE_CAP, GUIDANCE_CAP);
```

Expose per-provider elapsed time, prepared state, batch count, returned/accepted signal counts, cache details, and neutralized failures in the native result.

- [ ] **Step 5: Run optimizer tests**

Run: `cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml`

Expected: v2 host tests pass, no-provider behavior stays neutral, and repeated runs are deterministic.

- [ ] **Step 6: Commit host migration**

```powershell
git -C D:/LMS/bliss-playlist-optimizer add Cargo.toml Cargo.lock src/guidance.rs src/main.rs tests/contracts.rs
git -C D:/LMS/bliss-playlist-optimizer commit -m "feat: host bounded guidance SPI v2 sessions"
```

### Task 5: Move the optimizer's candidate ranking to provider guidance

**Files:**
- Modify: `D:/LMS/bliss-playlist-optimizer/src/main.rs`
- Modify: `D:/LMS/bliss-playlist-optimizer/src/preview.rs`
- Modify: `D:/LMS/bliss-playlist-optimizer/src/semantic.rs`
- Modify: `D:/LMS/bliss-playlist-optimizer/src/anchored_path.rs`
- Modify: `D:/LMS/bliss-playlist-optimizer/schemas/optimizer-request-v1.schema.json`
- Modify: `D:/LMS/bliss-playlist-optimizer/schemas/optimizer-result-v1.schema.json`
- Modify: `D:/LMS/bliss-playlist-optimizer/tests/contracts.rs`

**Interfaces:**
- Consumes `GuidanceBatch` from Task 4 and compact candidate identities verified against the local candidate inventory.
- Produces guided candidate order only after membership, genre, uniqueness, repeat-window, and Bliss acceptance filtering.
- Deletes direct `semantic_evidence` candidate selection/reranking and `artifacts.play_counts` loading from the migration branch.

- [ ] **Step 1: Add failing planner-boundary tests**

Test automatic extension, exact extension, spacing repair, preserved-order gap repair, and destination routing with equal Bliss candidates. Give the fixture provider one positive and one negative signal and assert guidance changes their order without admitting a non-shortlisted candidate.

```rust
assert_eq!(selection.added_track_ids, vec!["bliss-row-2"]);
assert!(!selection.added_track_ids.contains(&"bliss-row-excluded".to_owned()));
```

- [ ] **Step 2: Run the focused tests to demonstrate the direct paths still own ranking**

Run: `cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml planner_guidance -- --nocapture`

Expected: the positive provider signal does not yet affect all required planners.

- [ ] **Step 3: Add verified candidate-identity loading**

Add a request artifact for `eligible-candidate-identities-v1`. Validate its SHA-256, Bliss database cache identity, candidate ID/row-ID correspondence, allowed-row membership, and duplicate identities. Project `lms_urlmd5` only into score batches; do not add it to the decoded Bliss feature model.

- [ ] **Step 4: Introduce one shared guided ranking boundary**

Create a helper that receives an acoustic shortlist and route context, asks providers for bounded signals before CPU-parallel candidate evaluation, then passes an immutable adjustment map into parallel ranking:

```rust
fn rank_guided_shortlist(
    context: GuidanceContext<'_>,
    candidates: &[usize],
    acoustic: impl Fn(usize) -> CandidateEvaluation,
) -> Result<Vec<CandidateEvaluation>, CommandFailure>;
```

Use stable row-ID ordering before and after Rayon work. Call it from automatic/exact extensions, spacing repair, preserved-order gaps, and destination/A-to-B routes. Do not call a provider from inside a Rayon closure.

- [ ] **Step 5: Delete direct semantic and play-count ranking**

Remove `load_play_counts`, `PlayCountInventory`, `PlayCountTrack`, `RouteTrack::play_count_percentile` initialization, `GuidanceConfig` direct fields, and planner uses of `SemanticPool` as candidate admission/reranking. Keep only result-level provider provenance; candidate discovery is Bliss shortlist discovery.

- [ ] **Step 6: Update schemas and result provenance tests**

Remove `artifacts.play_counts` and obsolete caller-resolved Last.fm selection fields from the request schema. Add candidate identity artifact and trusted add-on descriptors. Ensure results report observed versus applied signals, provider source/snapshot details, and no private paths at INFO.

- [ ] **Step 7: Run the complete optimizer suite**

Run: `cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml`

Expected: all planners use the same guidance boundary; no direct play-count artifact test remains; results are stable under default and `RAYON_NUM_THREADS=1` runs.

- [ ] **Step 8: Commit the single-path ranking migration**

```powershell
git -C D:/LMS/bliss-playlist-optimizer add src/main.rs src/preview.rs src/semantic.rs src/anchored_path.rs schemas tests/contracts.rs
git -C D:/LMS/bliss-playlist-optimizer commit -m "feat: apply provider guidance at shared ranking boundaries"
```

### Task 6: Produce `urlmd5` candidate identities and trusted provider policy in Better Call Bliss

**Files:**
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/CandidateInventory.pm`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/RequestBuilder.pm`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/BlissCompatibility.pm`
- Modify: `D:/LMS/lms-better-call-bliss/tests/candidate_inventory_library.t`
- Modify: `D:/LMS/lms-better-call-bliss/tests/request_json_types.t`

**Interfaces:**
- Produces `bettercallbliss-candidate-identities-v1` entries including `candidate_id`, `row_id`, `lms_track_id`, and `lms_urlmd5`.
- Produces optimizer request references for the identity artifact, resolved Last.fm artifact, trusted `persist.db`, and bundled provider programs.
- Does not create `lms-play-counts-v1` artifacts.

- [ ] **Step 1: Extend the existing candidate-inventory fixture**

Select `tracks.urlmd5` while capturing the LMS library. Assert that only the selected virtual-library track's identity contains `lms_urlmd5` and that the identity artifact changes when that value changes.

```perl
is($first->{identities}->[0]->{lms_urlmd5}, 'allowed',
    'identity artifact preserves the LMS URLMD5 for provider lookup');
```

- [ ] **Step 2: Run the fixture to verify the field is absent today**

Run: `perl tests/candidate_inventory_library.t`

Expected: the new assertion fails before the SQL projection is updated.

- [ ] **Step 3: Add compact identity and resource descriptors**

Extend the LMS catalog query with `tracks.urlmd5`, include it in cached identities, and add a request-builder helper that creates trusted `guidance_addons` entries. It must use plugin installation paths and server capability data—not web form values—for program and `persist.db` paths.

```perl
guidance_addons => [
  { id => 'lastfm-guidance', program => $lastfm_binary, options => {...} },
  { id => 'playcount-guidance', program => $playcount_binary, options => {...} },
],
```

Pass SHA-256 values for both artifacts and `access => 'read-only'` for `persist.db`.

- [ ] **Step 4: Verify request JSON types and policy ownership**

Run: `perl tests/candidate_inventory_library.t; perl tests/request_json_types.t`

Expected: `lms_urlmd5` is present, provider paths come only from trusted capability state, and no user parameter can override them.

- [ ] **Step 5: Commit Better Call Bliss inventory/policy groundwork**

```powershell
git -C D:/LMS/lms-better-call-bliss add BetterCallBliss/CandidateInventory.pm BetterCallBliss/RequestBuilder.pm BetterCallBliss/BlissCompatibility.pm tests/candidate_inventory_library.t tests/request_json_types.t
git -C D:/LMS/lms-better-call-bliss commit -m "feat: provide trusted guidance identities and resources"
```

### Task 7: Replace the Better Call Bliss direct path and preserve UX diagnostics

**Files:**
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/Jobs.pm`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/CandidateInventory.pm`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/CandidateGuidance.pm`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/RequestBuilder.pm`
- Modify: `D:/LMS/lms-better-call-bliss/BetterCallBliss/LogDiagnostics.pm`
- Modify: `D:/LMS/lms-better-call-bliss/tests/candidate_inventory_library.t`
- Modify: `D:/LMS/lms-better-call-bliss/tests/candidate_guidance.t`
- Modify: `D:/LMS/lms-better-call-bliss/tests/log_diagnostics.t`

**Interfaces:**
- Consumes the optimizer/provider artifacts produced by Tasks 1–6.
- Produces immediate job progress through Last.fm preparation, candidate-identity capture, native provider preparation, and guided optimizer stages.
- Deletes `prepare_playcounts`, `prepare_playcounts_async`, `play-counts.json`, and direct selection/reranking code.

- [ ] **Step 1: Add failing job-orchestration tests**

Assert a play-count-enabled job launches after identity capture without scheduling `Preparing play-count guidance`, and that a missing/locked `persist.db` appears as neutral provider diagnostics in a completed preview rather than `PLAYCOUNT_PREPARATION_FAILED`.

```perl
unlike($job->{stage}, qr/Preparing play-count guidance/,
    'job does not build a full-library play-count artifact');
is($result->{guidance}->{playcount}->{state}, 'neutral',
    'SQLite provider failure remains advisory');
```

- [ ] **Step 2: Run the affected Perl tests to verify legacy behavior fails them**

Run: `perl tests/candidate_inventory_library.t; perl tests/candidate_guidance.t; perl tests/log_diagnostics.t`

Expected: current code still calls `prepare_playcounts_async` and writes `play-counts.json`.

- [ ] **Step 3: Remove the full-library play-count collector**

Delete `_playcount_query`, `_finish_playcount_snapshot`, `_capture_playcount_row`, `prepare_playcounts`, and `prepare_playcounts_async`, their tests, and Job fields that exist solely to track the artifact. Do not retain dormant compatibility helpers.

- [ ] **Step 4: Keep LastMix acquisition but hand ranking to the provider**

Retain `LastFmEvidence.pm` and `CandidateGuidance.pm` only for asynchronous LastMix retrieval and resolution into `semantic-evidence.json`. Remove any Perl-side selection/reranking result mutation. Populate the v2 provider artifact descriptor and let native result provenance determine observed/applied reporting.

- [ ] **Step 5: Update user-visible status and diagnostics**

Report `Preparing Last.fm guidance`, `Capturing candidate identities`, and native provider stages as one continuous job. At INFO log provider state and aggregate counts; at DEBUG include bounded provider details without private paths. Render neutral/unavailable/observed/applied separately in the preview.

- [ ] **Step 6: Run the Better Call Bliss regression suite**

Run: `Get-ChildItem tests -Filter *.t | ForEach-Object { perl $_.FullName }`

Expected: all plugin tests pass; no test expects a play-count JSON file; Last.fm offline behavior remains non-fatal.

- [ ] **Step 7: Commit the migration deletion**

```powershell
git -C D:/LMS/lms-better-call-bliss add BetterCallBliss tests
git -C D:/LMS/lms-better-call-bliss commit -m "feat: route Better Call Bliss guidance through SPI providers"
```

### Task 8: Add end-to-end determinism, performance, and packaging checks

**Files:**
- Create: `D:/LMS/bliss-playlist-optimizer/tests/guidance_performance.rs`
- Modify: `D:/LMS/bliss-playlist-optimizer/.github/workflows/ci.yml`
- Modify: `D:/LMS/lms-better-call-bliss/.github/workflows/release.yml`
- Modify: README files in all five repositories

**Interfaces:**
- Consumes all v2 components from pinned commits.
- Produces repeatable CI measurements and release packages containing matching optimizer and provider binaries.

- [ ] **Step 1: Add a 200k-identity performance fixture**

Generate SQLite and candidate-identity data in a test temp directory rather than committing a huge fixture. Measure provider prepare memory/time, bounded score payload size, cache reuse, and repeated score latency.

```rust
assert!(metrics.max_score_payload_bytes <= 256 * 1024);
assert_eq!(first.signals, repeat.signals);
assert!(metrics.cached_score_queries < metrics.uncached_score_queries);
```

- [ ] **Step 2: Add deterministic worker-count tests**

Run the same extension and destination fixtures with `RAYON_NUM_THREADS=1` and a supported multi-worker setting, then compare serialized route/provenance bytes.

```rust
assert_eq!(single_thread_artifact, multi_thread_artifact);
```

- [ ] **Step 3: Add cancellation and provider-timeout integration tests**

Use a blocking fixture provider and assert host termination closes it. Use a deliberately locked SQLite fixture and assert the optimizer returns a completed Bliss-only preview with a neutral play-count diagnostic.

- [ ] **Step 4: Run performance and full test suites**

Run:

```powershell
cargo test --manifest-path D:/LMS/bliss-playlist-guidance-spi/Cargo.toml
cargo test --manifest-path D:/LMS/bliss-guidance-lastfm/Cargo.toml
cargo test --manifest-path D:/LMS/bliss-guidance-playcounts/Cargo.toml
cargo test --manifest-path D:/LMS/bliss-playlist-optimizer/Cargo.toml
Get-ChildItem D:/LMS/lms-better-call-bliss/tests -Filter *.t | ForEach-Object { perl $_.FullName }
```

Expected: all tests pass, payloads remain bounded, and route output is byte-stable across tested Rayon worker counts.

- [ ] **Step 5: Pin compatible releases and publish only after green CI**

Update the optimizer's SPI dependency revision and the Better Call Bliss bundled provider manifests together. Build all platform binaries in GitHub Actions, run the test matrix before packaging, and publish aligned version notes that identify the SPI version and provider revisions.

- [ ] **Step 6: Commit performance and release safeguards**

```powershell
git -C D:/LMS/bliss-playlist-optimizer add tests .github README.md Cargo.toml Cargo.lock
git -C D:/LMS/bliss-playlist-optimizer commit -m "test: cover guidance scalability and determinism"
git -C D:/LMS/lms-better-call-bliss add .github README.md
git -C D:/LMS/lms-better-call-bliss commit -m "build: package matched guidance providers"
```

## Final verification and handoff

- [ ] Run the complete test matrix from Task 8 on clean checkouts of all five branches.
- [ ] Build release binaries for every supported Better Call Bliss platform and confirm their optimizer/provider versions are compatible.
- [ ] Deploy the matching plugin and binaries to a test Lyrion server without restarting an actively playing server until the user approves.
- [ ] Run one Last.fm-enabled extension, one negative play-count-preference extension, one destination route, one locked/missing-database neutral fallback, and one cancelled preview.
- [ ] Compare INFO/DEBUG logs and preview provenance to verify that observed guidance, applied guidance, cache state, provider timing, and neutral failure behavior are clear without leaking private paths at INFO.
- [ ] Merge only the tested migration branches; remove no stable-main implementation until that branch is accepted.
