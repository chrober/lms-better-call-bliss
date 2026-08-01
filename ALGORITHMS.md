# Mixing strategies and options

Better Call Bliss optimizes a complete saved playlist. This differs from
BlissMixer's normal queue-continuation task: instead of choosing only the next
few songs, it evaluates a route through an entire fixed or expanded collection.

Three choices are deliberately independent:

1. **Source-track order** decides whether original songs may move.
2. **Additional tracks** decides whether and how new songs may be selected.
3. **Mixing strategy** decides how musical continuity is scored.

This document describes the current 0.13.0 implementation. **Working** means the
mode can be selected in the Lyrion job editor. **Planned** means the option is
visible but disabled; its description is the intended capability, not a claim
that it currently runs.

## At a glance

| Choice | Status | Plain-English result |
| --- | --- | --- |
| Optimize source order | Working | Move the original songs into a smoother sequence. |
| Preserve source order and fill gaps | Working | Keep every original song in place and insert help only between them. |
| Reorder existing tracks only | Working | Improve flow without changing playlist membership. |
| Add automatically | Working | Add bridges only at difficult transitions, up to a limit. |
| Add exactly N tracks | Working | Add precisely N bridges or fail without returning a partial result. |
| Grow from these seeds | Working | Keep the source songs as the taste reference, select enough similar songs to reach a target size, then route the result. |
| One bridge per transition | Planned | Fill every original internal gap with one track. |
| Reach target length / double length | Planned | Convenience presets that calculate an exact addition count. |
| Adaptive dynamic weighting | Working | Let the recent musical context decide which Bliss features matter for each transition. |
| Static weighted distance | Planned | Use fixed user priorities for tempo, timbre, loudness, and harmony. |
| Random forest | Planned | Learn the common shape of several context songs and prefer candidates that fit it. |

## Architecture

The plugin prepares identities and settings, optional Last.fm evidence, and a
snapshot of the LMS-local Bliss rows. The native optimizer performs read-only
scoring and search. Only the plugin can create a playlist, and only after the
user accepts a completed Preview.

~~~mermaid
flowchart TD
    A["Saved Lyrion playlist"] --> B["Validate local tracks<br/>capture per-job options"]
    DB[("bliss.db<br/>23 Bliss features per song")] --> C
    M["learned_matrix.json"] --> C
    B --> D{"Tracks may be added?"}
    D -- No --> C["Native contextual route search"]
    D -- Yes --> I["Freeze LMS-local candidate inventory"]
    L["Optional LastMix evidence"] --> E
    I --> E["Native candidate selection<br/>and route search"]
    C --> R["Versioned result and proofs"]
    E --> R
    R --> P["Read-only Lyrion Preview"]
    P -->|"user accepts"| W["Create and verify a new playlist"]
~~~

## Similarity strategies

### Adaptive dynamic weighting — working

> **In plain English:** Adaptive asks what the immediately preceding songs have
> in common. If their harmony is consistent but their tempo varies, harmony
> receives more influence for the next transition. The definition of
> similarity therefore changes along the route instead of staying fixed for
> the whole playlist.

For each directional transition, the optimizer uses up to **Musical context
window** preceding tracks. With two or more context tracks it calculates a
variance-based weight matrix: features on which the context agrees receive
more weight, while inconsistent features receive less. That matrix is blended
with the learned Mahalanobis matrix according to **Learned-matrix blend**.
With one context track, variance cannot be calculated, so the learned matrix is
used directly.

A candidate distance is a Mahalanobis distance in the 23-feature Bliss space.
It is directional because the context before B to C is different from the
context before C to B.

~~~mermaid
flowchart TD
    A["Take up to N immediately<br/>preceding route tracks"] --> B{"Context size"}
    B -- "one" --> C["Use learned matrix"]
    B -- "two or more" --> D["Calculate variance-based<br/>dynamic matrix"]
    D --> E["Blend with learned matrix<br/>using learned percentage"]
    C --> F["Prepared Adaptive context"]
    E --> F
    F --> G["Score candidate with<br/>Mahalanobis distance"]
    G --> H["Append candidate to context<br/>before scoring the next leg"]
~~~

The learned matrix is not a separate strategy. It is a personalized component
inside Adaptive scoring. The current plugin requires the matrix file to be
present; a blend of zero means only the variance matrix influences multi-track
contexts, but the file is still a readiness requirement.

### Static weighted distance — planned

> **In plain English:** You decide in advance how much tempo, timbre, loudness,
> and harmony matter. Those priorities stay the same for every transition.

The intended route scorer uses one fixed weighted distance throughout a job.
This resembles BlissMixer's Static Weights mode, but Better Call Bliss does not
currently connect a native static route implementation or job-local weight
controls. Selecting it in the UI is therefore disabled.

### Random forest — planned

> **In plain English:** A forest model looks at several context songs, learns
> their common musical shape, and treats candidates that fit that shape as
> more suitable.

The intended implementation would train or derive an isolation-forest-style
context model and use its anomaly score as the transition score. The native
playlist route and bridge workflows do not currently connect this strategy.

~~~mermaid
flowchart LR
    S["Context tracks"] --> A{"Selected strategy"}
    A -- "Adaptive: working" --> AD["Dynamic variance and<br/>learned matrix"]
    A -- "Static: planned" --> ST["Fixed user weights"]
    A -- "Forest: planned" --> RF["Context distribution model"]
    AD --> D["Scalar transition distance"]
    ST --> D
    RF --> D
    D --> R["Common route, repeat,<br/>variation, and output layers"]
~~~

Keeping variation and route constraints downstream of the scoring strategy
allows future Static and Forest implementations to reuse the same search and
safety rules.

## Playlist workflows

### Reorder existing tracks only

> **In plain English:** Use every original song once, add nothing, and find an
> order with fewer awkward jumps.

The optimizer evaluates fixed starts and a configurable number of seeded
greedy restarts. Each candidate route is improved with reversal and relocation
moves. Artist and album look-back windows are hard feasibility constraints.
The primary objective is:

    transition sum + 2 × worst transition

This penalizes a single jarring jump more strongly than many small distances.
A second route search prefers a gradual energy arc whose peak is around 70% of
the playlist. It is selected only when its primary objective is within 8% of
the best primary route and its arc error improves by at least 10%.

~~~mermaid
flowchart TD
    A["Original fixed membership"] --> B["Fixed starts and seeded<br/>greedy restarts"]
    B --> C["Reversal and relocation<br/>local improvements"]
    C --> D{"Repeat windows valid?"}
    D -- No --> B
    D -- Yes --> E["Measure transition sum<br/>and worst transition"]
    E --> F["Primary route candidate"]
    B --> G["Energy-arc-aware search"]
    G --> H{"Within 8% objective<br/>and 10% better arc?"}
    H -- Yes --> I["Select arc route"]
    H -- No --> J["Select primary route"]
~~~

With **Variation** above zero, the generation seed changes the deterministic
restart paths. The same request and seed reproduce the same result.

### Add automatically

> **In plain English:** First find the route, then inspect its difficult joins.
> Add a bridge only when a transition is unusually hard and a candidate makes
> both new legs acceptable. Adding zero tracks is a valid outcome.

The optimizer freezes the distribution of contextual transition distances and
expresses gaps and candidate legs as percentiles of that reference. A gap is
eligible only when its direct percentile is above **Bridge trigger
percentile**. Gaps are processed from left to right against the evolving route,
up to **Maximum additional tracks**.

For each gap, semantic candidates are retained first and the remaining internal
shortlist is filled from the strict Adaptive acoustic rank, up to 256 tracks.
A candidate C between A and B is rescored as two directional legs:

1. history ending in A to C;
2. updated history ending in C to B.

Both legs must obey repeat constraints. The worse leg must be at or below the
70th reference percentile, and the sum of both leg percentiles must be at or
below 1.30. These are fixed native safety gates, not job controls.

~~~mermaid
flowchart TD
    A["Optimized or preserved source route"] --> B["Freeze contextual<br/>reference distribution"]
    B --> C["Inspect next internal gap"]
    C --> D{"Direct gap above<br/>trigger percentile?"}
    D -- No --> N["Keep gap unchanged"]
    D -- Yes --> E["Build semantic plus acoustic<br/>shortlist, maximum 256"]
    E --> F["Score A to C"]
    F --> G["Update history and score C to B"]
    G --> H{"Unique, repeat-safe,<br/>worst leg at most 0.70,<br/>detour at most 1.30?"}
    H -- No --> N
    H -- Yes --> I["Insert best accepted bridge"]
    I --> J{"Addition budget reached?"}
    N --> K{"More gaps?"}
    J -- No --> K
    J -- Yes --> R["Return final route and decisions"]
    K -- Yes --> C
    K -- No --> R
~~~

### Add exactly N tracks

> **In plain English:** Request a precise number of additions. Better Call
> Bliss either finds that complete result or explains that the constraints make
> it impossible; it never quietly returns fewer tracks.

The native optimizer performs bounded exact-count search across eligible gaps.
The current plugin enables only internal gaps, at most one added track per
source transition, and no opening or closing additions. For S source tracks the
current UI therefore permits at most S minus 1 additions. Multi-track gaps and
endpoint slots exist in the native engine but are not connected to this UI.

### Preserve source order and fill gaps

> **In plain English:** Treat the current playlist as a sequence of immovable
> anchors. Improve it by placing new songs between anchors without changing the
> story or chronology chosen by the user.

Preserve order is an ordering policy, not a separate similarity metric. It can
be combined with automatic or exact-count additions. The native result must
prove that all originals form the same ordered subsequence in the final route.
Preserve order plus no additions is rejected because it would change nothing.
Additional route-search attempts are irrelevant because the anchors may not
move.

~~~mermaid
flowchart LR
    A["Original A"] --> G1["Gap 1"]
    G1 --> B["Original B"]
    B --> G2["Gap 2"]
    G2 --> C["Original C"]
    G1 -.-> X["Optional added track"]
    G2 -.-> Y["Optional added track"]
~~~

### Grow from these seeds

> **In plain English:** Start with a small set that defines the musical
> neighborhood. Find enough suitable local songs to reach the requested size,
> then arrange all seeds and additions into a fluent playlist.

Every source track remains an immutable relevance seed and must appear exactly
once in the output. Newly selected songs never become relevance seeds, which
prevents the selection from drifting away from the original taste. All
LMS-local analyzed candidates are scored against one Adaptive context built
from the complete seed set.

The best candidates form a bounded quality pool. Variation can perform
reproducible weighted sampling inside that pool; Last.fm-endorsed artists can be
weighted toward the requested target. Artist and album capacities implied by
the repeat windows are applied during membership selection. The complete fixed
membership is then reordered with the normal route optimizer. Grow from seeds
therefore forces optimized source order.

~~~mermaid
flowchart TD
    A["Complete original seed set"] --> B["Build one immutable<br/>Adaptive relevance context"]
    C["All LMS-local analyzed tracks"] --> D["Score candidates in parallel"]
    B --> D
    D --> E["Rank by acoustic relevance"]
    L["Optional Last.fm<br/>artist endorsements"] --> F
    E --> F["Build bounded quality pool"]
    F --> G["Seeded weighted selection<br/>using Variation and artist target"]
    G --> H["Apply artist and album<br/>repeat capacities"]
    H --> I{"Exact target membership found?"}
    I -- No --> X["Fail without partial playlist"]
    I -- Yes --> J["Route seeds plus additions"]
    J --> K["Verify exact target, every seed,<br/>unique local membership,<br/>and repeat windows"]
~~~

## Per-job options

Defaults are copied from BlissMixer or Better Call Bliss settings when the job
editor opens. Changing a job never changes the BlissMixer global preferences.

| Option | Range / default | Effect and scope |
| --- | --- | --- |
| Source-track order | Optimize by default | Optimize may move originals. Preserve keeps them as immutable anchors and requires an addition mode. Seed growth always optimizes. |
| Additional tracks | None by default | Selects reorder-only, automatic, exact count, or seed growth. |
| Musical context window | 1-50; inherited from BlissMixer | Maximum number of immediately preceding tracks used for each Adaptive directional score. |
| Learned-matrix blend | 0-100%; inherited | Blend of learned and variance matrices for contexts with at least two tracks. |
| Artist look-back | 0-10,000; inherited | Forbids the same artist within that many preceding playlist positions. Zero disables it. |
| Album look-back | 0-10,000; inherited | Forbids the same album within that many preceding positions. Zero disables it. |
| Track look-back | 0-10,000; inherited | Retained for compatibility and proofs. Connected routes already require unique membership. |
| Additional route-search attempts | 0-500; default 50 | More seeded starts may find a better movable route but cost CPU time. Zero still evaluates built-in fixed starts. |
| Variation | 0-100%; default 25 | Seeds movable-route search. Seed growth additionally varies membership inside its quality pool. It does not weaken acoustic or repeat gates. |
| Generation seed | 0-4,294,967,295; blank by default | Blank derives a new per-job seed. Reusing the reported seed reproduces the same request. |
| Last.fm artist weighting | Off by default | Requires LastMix. Adds artist-similarity evidence when tracks may be selected. It has no effect on reorder-only membership. |
| Last.fm artist probability | 1-100%; default 25 | Seed growth treats this as a target endorsed-artist share when both groups exist. Bridge modes use artist evidence as a priority, not a guaranteed quota. |
| Maximum additional tracks | 0-100; default 8 | Upper bound for automatic additions. Zero makes automatic mode a no-op and is rejected with preserved order. |
| Bridge trigger percentile | 0-100%; default 70 | Automatic mode inspects only direct gaps above this contextual percentile. |
| Exact number of additions | 1-100; default 1 | Exact-count target, further limited by current internal-gap capacity S minus 1. |
| Final playlist size | 3-500; default 25 | Seed-growth target. It must be greater than the source size. |
| Output | Create copy | Preview is always read-only. Creating a verified copy is working; source overwrite is planned and unavailable. |

## Variation and reproducibility

Variation is downstream of the similarity strategy. It does not change the
Bliss feature vectors or relax constraints:

- movable routes use the generation seed for deterministic restart diversity;
- seed growth uses the seed for weighted membership selection;
- automatic and exact bridge acceptance remain deterministic acoustic and
  semantic searches after their base route has been chosen; and
- preserved-order bridge jobs can legitimately return the same result for
  different seeds because their anchors cannot move.

Variation zero requests strict best-match behavior. An explicit seed makes the
same inputs reproducible across worker counts.

## Last.fm artist guidance

Last.fm is optional and is accessed through LastMix without user credentials.
Better Call Bliss queries each distinct artist from the complete original
playlist. Evidence whose source matches a transition endpoint is preferred;
evidence from the complete artist pool is a fallback only when local evidence
is empty.

Last.fm never admits a track that failed local membership, acoustic, uniqueness,
or repeat checks. Missing LastMix, no Internet connection, malformed responses,
and provider errors fall back to Bliss. Service-offline, temporarily
unavailable, and rate-limit responses open a per-job circuit breaker so the
remaining source artists are not repeatedly queried.

## Safety and result proofs

Before searching for additions, the plugin intersects usable bliss.db rows with
the current local LMS catalog and sends a checksum-protected allowlist to the
optimizer. The native result is resolved back to LMS tracks and checked again
before persistence.

A successful result proves the invariants relevant to its workflow:

- every original track is retained exactly once;
- preserved-order originals remain the same ordered subsequence;
- every addition belongs to the frozen LMS-local inventory;
- membership is unique;
- requested exact or target counts are satisfied; and
- artist, album, and track repeat rules hold.

Preview writes no playlist. Only the separate user-confirmed copy action uses
Lyrion's playlist serializer and verifies both file and catalog order.
