# Local Library Signals v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the narrowly named play-count provider with one Lyrion-only
library-signals provider that can guide Better Call Bliss with play count,
last-played recency, and durable first-seen library age.  

**Architecture:** `bliss-guidance-playcounts` is renamed to
`bliss-guidance-library-signals`; it opens one read-only `persist.db` snapshot
per optimization and exposes `playcount`, `last_played`, and `library_age`
channels through the existing host-neutral guidance SPI. Better Call Bliss
starts it only when one signed preference is non-zero, supplies the trusted
database path and frozen identities, and presents the resulting signals as
optional Bliss-first guidance.  

**Terminology:** Alternative Play Count (**APC**) is a separate Lyrion plugin
which maintains its own play, skip, and dynamic-preference data. It is not a
source for this feature. Any future APC-derived guidance is a separate Rust
provider with its own settings, resource contract, packaging, and diagnostics.  

**Tech Stack:** Rust 2024, `rusqlite`, `bliss-guidance-jsonl-v2`, Perl/Lyrion
plugin templates and tests, GitHub Actions release packaging.  

**Spec:** `D:/LMS/bliss-similarity-design/LOCAL_LIBRARY_GUIDANCE_PLAN.md`  

## Global Constraints

- v1 reads only `persist.db.tracks_persistent`; it must not detect, open,
  configure, package, or require Alternative Play Count (APC), its database,
  or any APC preference.  
- Do not add an APC fallback or silently blend APC values with Lyrion values.
  APC-based play, skip, or affinity guidance belongs to a separate future Rust
  guidance provider, not to `bliss-guidance-library-signals`.  
- Use `urlmd5` identities and a read-only SQLite snapshot.  
- `playcount`, `last_played`, and `library_age` are normalized over the frozen
  eligible identity population; score calls query only bounded batches and use
  a job-local cache.  
- A value of `0` is neutral and does not start this provider if every local
  preference is zero. Positive values favor higher/more-recent/newer values;
  negative values favor their opposite.  
- Never let guidance admit a non-Bliss candidate or override virtual-library,
  genre, uniqueness, or repeat-window constraints.  
- Report `tracks_persistent.added` as Lyrion first-seen age, including its
  first-library-scan file-timestamp caveat; do not use `tracks.added_time`.  
- All provider errors, unavailable statistics, invalid schema, and missing
  identity rows are neutral and visible in diagnostics.  

## Review Focus

- A non-zero recency or age control with an unavailable `persist.db` yields a
  valid Bliss-only preview with an unavailable-provider diagnostic.  
- An unplayed track normalizes as the oldest last-played value, so negative
  recency can rediscover it and positive recency does not favor it.  
- The oldest and newest known `added` values score as exact opposites under
  `-100` and `100` policies.  
- A candidate missing from `tracks_persistent` is neutral rather than treated
  as newly added, newly played, or an error.  
- Existing play-count behavior remains equivalent after the binary/provider
  rename, including neutral operation when its control is zero.  

### Task 1: Rename and generalize the Rust provider

**Files:**
- Rename repository/package/binary: `bliss-guidance-playcounts` →
  `bliss-guidance-library-signals`.  
- Modify: `Cargo.toml`, `src/main.rs`, `README.md`, GitHub workflow/release
  metadata.  
- Test: `src/main.rs` unit tests.  

**Interfaces:**
- Consumes: trusted `persist_db` read-only resource and frozen `urlmd5`
  population through `bliss-guidance-jsonl-v2`.  
- Produces: provider ID `library-signals-guidance` with the channels
  `playcount`, `last_played`, and `library_age`.  

- [ ] **Step 1: Write failing tests for the expanded manifest and signals.**
  Assert that the manifest advertises the new provider ID and all three
  channels, a fixture with old/new/never-played rows emits monotonic normalized
  signals, and an unknown URL MD5 emits no signal.  
- [ ] **Step 2: Run the focused provider tests and verify the new assertions
  fail because only `playcount-guidance` exists.**  
  Run: `cargo test manifest_identifies_library_signals -- --exact`  
  Expected: failure due to the missing test/provider identity.  
- [ ] **Step 3: Implement `LibrarySignalsState`.**
  In `prepare`, validate `tracks_persistent(urlmd5, playCount, lastPlayed,
  added)`, stream the frozen identity population once, and retain three compact
  percentile distributions plus a bounded `urlmd5` cache. In `score`, fetch
  only cache misses with an indexed `IN (...)` query and emit the available
  channel values. Map null/zero `lastPlayed` to the oldest recency rank and
  leave absent rows neutral. Do not add APC detection, resources, schema
  handling, or fallback behavior.  
- [ ] **Step 4: Rename public identities.**
  Rename the package, executable, program/version metadata, provider ID,
  README, and GitHub repository to `bliss-guidance-library-signals`; retain the
  `playcount` channel name but do not retain an old duplicate executable.  
- [ ] **Step 5: Run provider verification.**
  Run: `cargo fmt --check; cargo test; cargo clippy -- -D warnings`.  
- [ ] **Step 6: Commit the provider migration.**  

### Task 2: Wire three signed preferences into Better Call Bliss

**Files:**
- Modify: `BetterCallBliss/Plugin.pm`, `BlissCompatibility.pm`,
  `RequestBuilder.pm`, `JobOptions.pm`, `Web.pm`, `GuidanceReporting.pm`,
  `LogDiagnostics.pm`, `Jobs.pm`, `strings.txt`, and
  `HTML/EN/plugins/BetterCallBliss/index.html`.  
- Modify: `BetterCallBliss/Bin/SOURCE.md`, packaging workflow, plugin tests.  

**Interfaces:**
- Consumes: `bliss-guidance-library-signals` executable, its SPI v2 manifest,
  and `persist.db`.  
- Produces: signed job options `playcount_influence`, `last_played_influence`,
  and `library_age_influence`; one `library-signals-guidance` add-on and up to
  three guidance-policy entries.  

- [ ] **Step 1: Write failing Perl tests.**
  Assert that a `last_played_influence => -80` request starts the new provider,
  creates a negative `last_played` policy, and never starts it when all three
  controls are zero. Add equivalent assertions for `library_age_influence` and
  migrated play-count policy construction.  
- [ ] **Step 2: Run the focused tests and verify they fail because the two
  options and new provider ID are absent.**  
- [ ] **Step 3: Implement capability detection and request construction.**
  Replace the play-count binary lookup with the library-signals executable;
  preserve read-only `persist.db` resource validation; emit policies only for
  non-zero values; set new Better Call Bliss global defaults to `0`. Do not
  expose an APC source selector or APC settings in this release.  
- [ ] **Step 4: Add the per-job Listening preferences controls.**
  Keep play count, last played, and library age in one conditional section;
  use signed `-100..100` Material-compatible sliders; explain the two
  directions and the first-seen timestamp caveat.  
- [ ] **Step 5: Update results and diagnostics.**
  Show each selected addition's applied local channels, provider coverage,
  neutral/missing-row counts, and unavailable fallbacks without paths or raw
  listening history.  
- [ ] **Step 6: Run the plugin suite and commit the integration.**  

### Task 3: Contract, packaging, real-Pi verification, and release

**Files:**
- Modify where required: `bliss-playlist-guidance-spi` contract tests/docs and
  `bliss-playlist-optimizer` contract fixtures/docs.  
- Modify: Better Call Bliss release workflow and extension-repository entries
  for every supported provider platform binary.  
- Modify: the renamed provider `README.md`; Better Call Bliss `README.md`,
  `docs/GUIDANCE_DATA_FLOW.md`, `BetterCallBliss/Bin/SOURCE.md`, and
  `IMPROVEMENT_BACKLOG.md`; and
  `D:/LMS/bliss-similarity-design/LOCAL_LIBRARY_GUIDANCE_PLAN.md`.  
- Test: provider/optimizer/Better Call Bliss suites and Pi preview artifacts.  

**Interfaces:**
- Consumes: the renamed provider's v2 manifest and generic channel signals.  
- Produces: release packages that bundle the renamed provider and live previews
  with explanatory local-guidance results.  

- [ ] **Step 1: Add contract regressions.**
  Prove generic SPI parsing accepts the new provider and all three channels,
  while an unknown provider/channel remains isolated and neutral.  
- [ ] **Step 2: Build all supported provider binaries in GitHub Actions and
  ensure Better Call Bliss packages them without committing binaries.**  
- [ ] **Step 3: Deploy the matching Better Call Bliss code and provider binary
  to `192.168.1.111` without deleting existing user data.**  
- [ ] **Step 4: Run real previews on the Pi.**
  Verify one positive and one negative setting for each of play count,
  last-played, and library age; verify all-zero gives Bliss-only output; verify
  a deliberately unreadable database fails neutrally.  
- [ ] **Step 5: Update product documentation before release.**
  Rename and rewrite the provider README around its three Lyrion-only signals;
  document the one-snapshot/bounded-batch flow and explicit APC exclusion in
  Better Call Bliss's README and `docs/GUIDANCE_DATA_FLOW.md`; update
  `BetterCallBliss/Bin/SOURCE.md` for the renamed binary; mark the delivered
  backlog rows and library-guidance plan status accurately; and link the SPI
  contract to the new provider identity.  
- [ ] **Step 6: Commit/push coordinated changes and publish the release.**  
