# Post-scan candidate-library cache refresh

**Status: proposed, not implemented.** This document records the intended
behavior and the investigation so far. It does not describe an existing
automatic refresh or promise that a particular coordination mechanism works.

## Motivation

The first Better Call Bliss preview or **Bliss me there...** action after a
Lyrion library scan can spend substantial time rebuilding the candidate
library. A user observed roughly a minute in that phase. Subsequent runs can
reuse a valid cache. The aim is to move that work out of the first interactive
request without making playback or the Lyrion web interface unresponsive.

## Current behavior

- `CandidateInventory.pm` builds a candidate inventory from local Lyrion audio
  tracks and usable `bliss.db` rows. It stores per-scope state and artifacts,
  including candidate and track identities. The inventory is needed for safe
  candidate selection, not merely for the user interface.
- Reuse is conditional on the Bliss database identity, last Lyrion scan time,
  configured media roots, candidate-library scope and membership, builder
  revision, and artifact validation. A mismatch causes a rebuild; a job also
  checks the Bliss database identity before accepting native results.
- The shared track-identity snapshot is not presently independent of
  `bliss.db`: its metadata includes the database identity, and parts of the
  identity data use Bliss artist credits. Waiting for analysis to finish does
  not by itself remove that dependency.
- On Unix-like systems the existing asynchronous inventory builder forks a
  worker and requests reduced CPU priority and idle I/O priority. Its tasks use
  one FIFO queue. It is not yet a post-scan warmer and does not currently merge
  a foreground request with an equivalent background task. On Windows, the
  current fallback runs preparation on the server side; it must not simply be
  reused for unattended background rebuilding without addressing responsiveness.
- BlissMixer has an optional post-scan importer that can start its analyser.
  Its start and completion are distinct from the Lyrion scanner completing;
  automatic analysis may be disabled or unavailable. The analyser also supports
  manual operation and can change `bliss.db` at other times.

Implementation references: [`CandidateInventory.pm`](../BetterCallBliss/CandidateInventory.pm),
[`Jobs.pm`](../BetterCallBliss/Jobs.pm), and the existing cache description in
[`ARCHITECTURE.md`](ARCHITECTURE.md). The BlissMixer importer and analyser live
in the [upstream plugin repository](https://github.com/CDrummond/lms-blissmixer).

## Agreed behavior

- Offer an opt-in Better Call Bliss setting for automatic background refresh
  after a completed Lyrion scan. Leave the setting off by default.
- Refresh only scopes for which Better Call Bliss already has a persisted
  candidate-library cache. Do not eagerly create caches for every virtual
  library. Include the unrestricted scope only if it was previously cached;
  skip removed or unavailable virtual libraries safely.
- Schedule work asynchronously at low resource priority, without blocking the
  Lyrion event loop or interfering noticeably with playback. Coalesce repeated
  scan notifications instead of launching duplicate rebuilds.
- If an interactive preview or destination action needs a scope being warmed,
  share the in-progress work and raise its effective throughput to the normal
  interactive level. If it needs a different scope, prioritize that request
  rather than making it wait behind all pending warm-ups. Preserve correct
  progress, cancellation and error reporting for every requesting job.
- Coordinate with BlissMixer's automatic post-scan analysis: normally wait
  until the relevant analysis has completed before preparing Bliss-dependent
  cache data. Do not wait indefinitely when automatic analysis is disabled,
  unavailable, fails or never starts. A user request must remain usable while
  analysis or warming is pending; it must not silently receive stale data.
- Build a coherent snapshot and validate its source identities before
  publishing or reusing it. A new scan, changed library membership, or a
  changing/replaced `bliss.db` must invalidate or cancel obsolete work and
  cause a safe retry or an explicit failure. Never publish a partially written
  or stale cache as valid. Retain the existing job-level validation as a
  separate safeguard.

## Design questions for implementation

- Determine a reliable, supported way to detect scanner and analyser lifecycle,
  including the race between scan completion and analyser startup. The current
  BlissMixer importer sends an analyser start command; scanner completion alone
  is not proof that analysis has finished. Manual analysis and failed starts
  need explicit handling too.
- Decide how to represent an in-flight build and attach multiple subscribers,
  including how cancellation of one preview differs from cancellation of work
  still needed by another preview or by background warming.
- Choose a safe promotion/preemption mechanism. Merely lowering a Unix
  worker's nice value or setting idle I/O priority may not be reversible by an
  unprivileged process. Cooperative throttling with a promotion signal is one
  option; a different-scope request also needs a safe scheduling strategy.
  Avoid concurrent publication races and avoid killing a worker while leaving
  its temporary artifacts or SQLite state inconsistent.
- Explore separating a reusable **Lyrion-only** track snapshot from the
  Bliss-dependent intersection. This could reduce repeated LMS work while the
  Bliss mapping is rebuilt after analysis, but requires separating fields and
  invalidation keys correctly; it is not a reason to weaken validation or a
  prerequisite already proven necessary for this feature.
- Define lifecycle and recovery for server shutdown, plugin disablement,
  repeated scans, stale workers, unavailable databases, removed libraries,
  permission errors and disk exhaustion. Avoid an always-running polling loop
  when no refresh is pending.
- Verify behavior on supported platforms; do not claim the current Windows
  synchronous fallback provides safe background processing.

## Acceptance and verification

- With opt-in disabled, scans do not start a warm-up. With it enabled, a scan
  schedules only previously cached scopes; repeated notifications coalesce.
- Exercise no analyser, disabled auto-analysis, delayed startup, successful
  completion, failure, manual analysis and another scan during the update.
- Exercise same-scope joining and promotion, different-scope priority,
  simultaneous requests, cancellation, shutdown and worker failure. Confirm
  that interactive job progress and existing notifications still work.
- Verify changed Bliss identity, scan generation, roots and virtual-library
  membership cannot result in stale or partial published caches. Verify cold
  and warm results against the existing inventory and identity contracts.
- Measure CPU, I/O, memory, playback and web responsiveness on a Raspberry Pi,
  including cold-start and representative large libraries. Compare an
  interactive request during warm-up with a normal on-demand rebuild and record
  actual timings; no speedup or resource target has yet been verified.
- Cover localized settings, unit and integration tests, and explicitly report
  which platforms and live scenarios were actually tested.
