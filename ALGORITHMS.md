# Playlist optimization modes and options

Better Call Bliss turns a saved playlist into a smoother listening experience. You decide whether existing songs may move, whether new songs may be added, and how much freedom the optimizer has. Better Call Bliss previews the result, and nothing is saved until you accept it.

This document describes the current 0.13.0 implementation. **Working** means the choice is available in the Lyrion job editor. **Planned** means it is shown but cannot yet be selected.

## Choose the result you want

| If you want to… | Choose… | What happens |
| --- | --- | --- |
| Smooth out a shuffled collection without adding songs | Optimize source order + Reorder only | The same songs are rearranged. |
| Keep a carefully chosen order but soften awkward changes | Preserve source order + Add automatically | Original songs stay put; helpful songs may be inserted between them. |
| Make a playlist exactly N songs longer | Optimize or Preserve + Add exactly N tracks | Exactly N suitable local songs are inserted, or the job explains why it cannot do so. |
| Turn a tiny playlist into a full mix with the same general character | Grow from these seeds | Every original song stays; similar local songs are selected until the target size is reached; then the complete set is arranged. |
| Get a different but still sensible result | Increase Variation | Search explores different good alternatives without relaxing its quality and repeat rules. |
| Favor artists related to the original artists | Enable Last.fm artist weighting | Last.fm guides song selection; Bliss remains the acoustic quality check. |

Three job choices work together:

1. **Source-track order** decides whether songs already in the playlist may move.
2. **Additional tracks** decides whether the playlist keeps its membership, repairs selected gaps, gains an exact number of songs, or grows from a seed collection.
3. **Mixing strategy** supplies the similarity measurement used by those playlist operations. Better Call Bliss reuses this capability from BlissMixer; it is not the main feature being selected here.

## Features at a glance

| Choice | Status | Listener-facing result |
| --- | --- | --- |
| Optimize source order | Working | Rearrange the original songs into a smoother sequence. |
| Preserve source order and fill gaps | Working | Keep the originals in their chosen order and insert help between them. |
| Reorder existing tracks only | Working | Change the order, not the contents. |
| Add automatically | Working | Repair only transitions that need it, up to a limit. |
| Add exactly N tracks | Working | Add the requested number or return no partial result. |
| Grow from these seeds | Working | Use all originals as a musical mood board and build a larger playlist around them. |
| One bridge per transition | Planned | Put one additional song in every gap. |
| Reach target length / double length | Planned | Convenience presets that calculate how many songs to add. |
| Adaptive dynamic weighting | Working | Use BlissMixer’s adaptive similarity measurement for each decision. |
| Static weighted distance | Planned | Reuse BlissMixer’s fixed user priorities. |
| Random forest | Planned | Reuse BlissMixer’s model of the sound shared by several example songs. |

## How the pieces fit together

The Better Call Bliss plugin resolves Lyrion tracks, reads per-job options, freezes the LMS-local candidate inventory, and optionally asks LastMix for Last.fm artist relationships. The native [bliss-playlist-optimizer](https://github.com/chrober/bliss-playlist-optimizer) performs scoring and bounded search. Only the plugin writes a playlist, and only after the user accepts a completed Preview.

~~~mermaid
flowchart TD
    P["Saved Lyrion playlist<br/>original source tracks"] --> O["Per-job ordering,<br/>extension, scoring,<br/>repeat and variation options"]
    DB[("bliss.db<br/>23 features per analyzed track")] --> I["Intersect Bliss rows with<br/>current local LMS library"]
    M["learned_matrix.json<br/>optional to BlissMixer;<br/>currently required here"] --> N
    O --> N["Native optimizer request"]
    I --> N
    L["Optional LastMix<br/>artist relationships"] --> N
    N --> S["Choose source route<br/>or preserve anchors"]
    S --> X{"Additional tracks"}
    X -- None --> R["Final route"]
    X -- Automatic or exact --> B["Gap-specific bridge search"]
    X -- Seed growth --> G["Complete-seed relevance search<br/>then final route search"]
    B --> R
    G --> R
    R --> V["Result artifact and proofs"]
    V --> Q["Read-only Preview"]
    Q -->|"user accepts"| W["Lyrion playlist writer"]
~~~

## Playlist workflows

Each working workflow below lists only the controls that can affect it. Defaults are copied from BlissMixer or Better Call Bliss settings when the editor opens; changing a job never changes those global preferences.

### Reorder existing tracks only

Imagine writing every song on a card and asking a DJ to lay out all the cards. No card may be removed or duplicated, and no new card may be added. The DJ tries many arrangements and keeps one whose handovers feel smooth, paying extra attention to avoiding one especially unpleasant jump.

The result may start with any song. It may also build gently toward a livelier section and ease back afterward, but only when that shape does not noticeably damage the musical transitions.

#### Options for Reorder only

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Source-track order | Optimize | Required: Preserve plus no additions would leave the playlist unchanged. |
| Musical context window | 1–50; inherited from BlissMixer | Maximum number of immediately preceding route tracks used to judge each possible next song. |
| Learned-matrix blend | 0–100%; inherited | Learned share for contexts of at least two tracks. The current one-track behavior is explained under Adaptive scoring. |
| Artist look-back | 0–10,000; inherited | Forbids the same artist within that many preceding positions. Zero disables it. |
| Album look-back | 0–10,000; inherited | Forbids the same album within that many preceding positions. Zero disables it. |
| Additional route-search attempts | 0–500; default 50 | Adds seeded greedy starting routes. Zero still evaluates the built-in starts. |
| Variation | 0–100%; default 25 | Zero uses a fixed baseline route seed; any positive value uses the job’s generation seed. |
| Generation seed | 0–4,294,967,295; generated by default | When Variation is positive, reusing the reported seed reproduces the same search. |
| Output | Create copy | Preview is read-only. Creating a verified copy works; source overwrite is planned. |

#### How the order is chosen

For every proposed position after the first, the optimizer compares each possible next song with up to **Musical context window** immediately preceding songs in that proposed route. At the start only one preceding song may exist; farther into the playlist the full window is available. The first song has no incoming transition and therefore no similarity score.

The search evaluates:

- the original order;
- the reverse order;
- for the energy-aware search, an intensity-sorted start; and
- the configured number of seeded greedy restarts.

A greedy restart chooses a seeded first song. At each following position it scores unused songs against the current preceding context, strongly preferring the best of the top four. Each completed start is repeatedly improved by reversing a section or relocating one song. The changed route is then scored again because moving one song can alter several later context windows.

Artist and album look-back windows are hard constraints. A final route that violates either is rejected. Track repetition cannot occur because every fixed member is used exactly once.

The primary objective is:

    sum of all transition distances + 2 × the worst transition

The extra penalty makes one severe jump more important than its contribution to the sum alone.

In parallel, an energy-aware search favors a broad rise from approximately 0.25 intensity to 0.85 near 70% of the playlist, then a fall toward approximately 0.35. Intensity is a rank-based composite of five Bliss features. This route replaces the best purely transition-oriented route only if:

- its primary objective is no more than 8% worse; and
- its energy-arc error is at least 10% better.

~~~mermaid
flowchart TD
    A["Fixed playlist membership"] --> B["Original, reverse and<br/>seeded greedy starts"]
    B --> C["Compare every possible next song<br/>with the preceding context"]
    C --> D["Reverse sections and relocate songs<br/>until no local move improves the route"]
    D --> E{"Artist and album<br/>windows satisfied?"}
    E -- No --> X["Reject attempt"]
    E -- Yes --> F["Measure total distance<br/>and worst transition"]
    F --> G["Best transition route"]
    B --> H["Parallel energy-aware search"]
    H --> I{"Within 8% transition cost<br/>and at least 10% better arc?"}
    I -- Yes --> J["Use energy-aware route"]
    I -- No --> G
~~~

### Preserve source order and fill gaps

Your original songs become fixed stepping stones. Better Call Bliss may place new stones between them, but it cannot swap or move the originals.

For example, A → B → C can become A → X → B → Y → C, but never B → A → C. This is useful for chronological playlists, albums, stories, or any sequence whose order already matters to you.

#### Options for Preserve source order

Preserve is an ordering policy used with **Add automatically** or **Add exactly N tracks**. The chosen addition workflow supplies its remaining controls.

| Option | Range / default | Effect with preserved anchors |
| --- | --- | --- |
| Source-track order | Preserve | Keeps every original track as an immutable ordered anchor. |
| Musical context window | 1–50; inherited from BlissMixer | Controls the preceding context used for direct gaps and both legs of an inserted bridge. |
| Learned-matrix blend | 0–100%; inherited | Controls Adaptive scoring for those contexts. |
| Artist look-back | 0–10,000; inherited | Applied to the source-anchor pre-check and final route. Zero disables it. |
| Album look-back | 0–10,000; inherited | Applied to the source-anchor pre-check and final route. Zero disables it. |
| Last.fm artist weighting | Off by default | Optionally prioritizes endpoint-local or original-collection artist relationships when choosing additions. |
| Output | Create copy | Preview is read-only. Creating a verified copy works; source overwrite is planned. |

#### How the anchors are protected

The input sequence is used directly as the source route. It is scored but not searched. The final result must prove that filtering out every added song yields the exact original sequence.

The source anchors must already satisfy the requested repeat windows. The current pre-check rejects an existing anchor conflict before trying insertions, even though a future implementation could attempt to separate those anchors with added tracks. Today such a job fails with a preserved-anchor conflict.

Additional route-search attempts have no effect because the anchors cannot move. Preserve plus **Reorder only** is rejected because it would leave the playlist unchanged.

### Candidate library for all addition modes

When Better Call Bliss adds music, it chooses only analyzed songs that Lyrion currently knows as local tracks. A stale Bliss database row cannot become a playlist entry merely because its acoustic data still exists.

#### How eligible candidates are frozen

Before search, the plugin intersects usable rows in bliss.db with the current local LMS catalog. From that intersection it excludes:

- every source file already in the playlist; and
- another file with the same normalized artist-and-title identity as a source.

The remaining tracks form a checksum-protected candidate inventory for this job. Uniqueness and repeat rules are checked again during search, when the native result is resolved back to LMS tracks, and before persistence.

### Add automatically

Better Call Bliss first decides the order of the original songs—or respects your order if you chose Preserve. It then listens to each handover and asks: “Is this one of the awkward changes, and can one extra song genuinely improve it?”

Suppose the playlist contains A followed by B. A candidate C is used only if A → C and C → B both work. It is not enough for C to resemble only A or only B. If the original transition is already fine, or no candidate improves it safely, nothing is inserted. Therefore **Add automatically** can correctly add zero songs.

#### Options for Add automatically

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Source-track order | Optimize by default | Either optimizes the originals before gap repair or preserves them as anchors. |
| Musical context window | 1–50; inherited from BlissMixer | Controls the preceding context for direct gaps and both candidate legs. |
| Learned-matrix blend | 0–100%; inherited | Controls Adaptive scoring for those contexts. |
| Artist look-back | 0–10,000; inherited | Rejects tentative and final routes with artists too close together. Zero disables it. |
| Album look-back | 0–10,000; inherited | Rejects tentative and final routes with albums too close together. Zero disables it. |
| Additional route-search attempts | 0–500; default 50 | Applies only when source order is Optimize. |
| Variation | 0–100%; default 25 | Can vary the optimized source route; it has no separate random bridge-selection step. |
| Generation seed | 0–4,294,967,295; generated by default | Reproduces the optimized source route when source order may move. |
| Last.fm artist weighting | Off by default | Enables categorical semantic priority. The numeric artist probability does not affect bridge rank. |
| Maximum additional tracks | 0–100; default 8 | Stops insertion after this many bridges. |
| Bridge trigger percentile | 0–100%; default 70 | Considers only original gaps above this point on the frozen reference scale. |
| Output | Create copy | Preview is read-only. Creating a verified copy works; source overwrite is planned. |

#### How difficult gaps are recognized

Raw similarity distances from different parts of a playlist are not directly comparable because their preceding contexts differ. For a direct transition A → B, B is compared with up to **Musical context window** preceding songs ending in A. Better Call Bliss therefore builds one frozen reference distribution before adding anything.

At every position in the selected source route, it scores original source songs that are not in that position’s context against that context. The sorted source-to-context distances become the job’s scale. A percentile means “how this distance compares with many alternatives drawn from the original playlist.” It is not percentage similarity, and the reference is not built from the complete music library.

An original gap is eligible only when its direct distance is above **Bridge trigger percentile**.

#### How candidates are chosen for one gap

For a gap A → B, optional Last.fm guidance is used in this order:

1. **Endpoint-local:** tracks whose artists Last.fm relates to A’s or B’s artist.
2. **Collection fallback:** used only if no endpoint-local candidate exists; tracks may relate to any artist in the complete original playlist.
3. **Bliss only:** used if neither Last.fm pool produces a candidate.

The plugin asks LastMix about every distinct artist in the original playlist. Current Last.fm evidence is artist-level only. The optimizer’s evidence contract also supports recording-level evidence for possible future providers.

If the selected pool contains more than 256 tracks, up to 32 highest-priority semantic matches are reserved. Acoustic two-leg ranking fills the remaining shortlist positions. Candidate identities and semantic evidence are then frozen for that original gap.

#### How a bridge is tested

For C inserted between A and B:

- **Left leg:** compare C with up to N preceding tracks ending in A.
- **Right leg:** insert C, then compare B with the updated preceding context ending in C.

N is **Musical context window**. With N = 3 and a route ending W → X → A → B, the left context is W, X, A and the candidate is C. For the second leg the context becomes X, A, C and the candidate is B. W drops out of the window.

~~~mermaid
flowchart LR
    P["… W → X → A"] --> C["candidate C"]
    C --> B["original B"]
    L["Left leg:<br/>context W, X, A<br/>candidate C"] -.-> C
    R["Right leg:<br/>context X, A, C<br/>candidate B"] -.-> B
~~~

Each leg is converted to a percentile on the frozen source-based scale. C is admissible only when:

- it is not already in the route;
- the full tentative route satisfies artist and album windows;
- the worse leg is at or below percentile 0.70; and
- the two leg percentiles sum to at most 1.30.

Admissible candidates rank by semantic evidence first, then by the better worst leg, then by the smaller two-leg sum, with a stable identity tie-break. These fixed native gates are not currently job controls.

#### How automatic insertion proceeds

Original gaps are processed from left to right. A bridge selected earlier becomes part of the preceding context used to score later bridge candidates.

The best admissible candidate is inserted only if its local objective improves on the direct gap:

    (left distance + right distance) + 2 × max(left distance, right distance)
        < direct distance + 2 × direct distance

Processing stops at **Maximum additional tracks**. A gap below the trigger, a depleted budget, a repeat conflict, failed acoustic gates, or no genuine improvement remains unchanged.

~~~mermaid
flowchart TD
    A["Selected or preserved source route"] --> B["Build frozen source-based<br/>distance distribution"]
    B --> C["Inspect original gaps<br/>from left to right"]
    C --> D{"Direct gap above trigger?"}
    D -- No --> N["Leave gap unchanged"]
    D -- Yes --> E["Choose endpoint-local,<br/>collection fallback or<br/>Bliss-only pool"]
    E --> F["Shortlist at most 256 tracks"]
    F --> G["Score context-ending-A → C"]
    G --> H["Insert C into context<br/>and score → B"]
    H --> I{"Unique, repeat-safe,<br/>both gates pass and<br/>local objective improves?"}
    I -- No --> N
    I -- Yes --> J["Insert best bridge"]
    J --> K{"Budget or gaps exhausted?"}
    N --> K
    K -- No --> C
    K -- Yes --> R["Return result and decisions"]
~~~

### Add exactly N tracks

This asks for a result of a specific size. Better Call Bliss considers different gaps and combinations instead of simply filling the first N gaps. It succeeds only when it can place all N songs while keeping every transition and repeat rule acceptable. Otherwise it returns an explanation rather than quietly producing fewer additions.

The current plugin can add at most one song between each pair of original songs. It does not add a song before the first or after the last original song.

#### Options for Add exactly N tracks

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Source-track order | Optimize by default | Either optimizes the originals before insertion or preserves them as anchors. |
| Musical context window | 1–50; inherited from BlissMixer | Controls both contextual legs of every candidate insertion and final route scoring. |
| Learned-matrix blend | 0–100%; inherited | Controls Adaptive scoring for those contexts. |
| Artist look-back | 0–10,000; inherited | Rejects candidate combinations and final routes with artists too close together. Zero disables it. |
| Album look-back | 0–10,000; inherited | Rejects candidate combinations and final routes with albums too close together. Zero disables it. |
| Additional route-search attempts | 0–500; default 50 | Applies only when source order is Optimize. |
| Variation | 0–100%; default 25 | Can vary the optimized source route; exact bridge combination search remains deterministic afterward. |
| Generation seed | 0–4,294,967,295; generated by default | Reproduces the optimized source route when source order may move. |
| Last.fm artist weighting | Off by default | Enables categorical semantic priority. The numeric artist probability does not affect bridge rank. |
| Exact number of additions | 1–100; default 1 | Required total, further limited by the current internal-gap capacity of S − 1. |
| Output | Create copy | Preview is read-only. Creating a verified copy works; source overwrite is planned. |

#### How the exact combination is found

Exact mode uses the same candidate inventory, Last.fm fallback order, two-leg contextual scoring, repeat constraints, and fixed acoustic gates as automatic mode. It does not use the automatic trigger and does not simply take the first eligible gaps.

At each original gap the search branches into **skip this gap** and the best admissible insertion choices. After each insertion it re-evaluates the objective for the complete evolving route. States are grouped by their current number of additions, and only a bounded set of the best routes continues. The current native beam width is 64; the plugin supplies up to five retained candidate alternatives per gap.

At the end, the optimizer selects the best route containing exactly N additions. If no retained route reaches N, it returns no partial playlist and reports whether the requested count exceeded structural capacity or was not found within the bounded search.

The current plugin requests one bridge at most per internal original gap and disables opening and closing slots. With S source songs, the UI therefore allows no more than S − 1 additions. The native optimizer already contains bounded multi-track-gap and endpoint support, but those controls are not connected.

~~~mermaid
flowchart TD
    A["Original route"] --> B["First original gap"]
    B --> C["Branch: skip or insert one<br/>admissible bridge candidate"]
    C --> D["Re-score each complete<br/>evolving route"]
    D --> E["Group by addition count<br/>and retain best bounded states"]
    E --> F{"More original gaps?"}
    F -- Yes --> C
    F -- No --> G{"A retained route<br/>contains exactly N additions?"}
    G -- No --> X["Fail without partial output"]
    G -- Yes --> H["Return the best exact-count route"]
~~~

### Grow from these seeds

This is for a small playlist that says “more music like this.” Every original song acts as part of one musical mood board. Better Call Bliss searches the analyzed songs in your local Lyrion library for tracks that fit that complete mood board, selects enough to reach the requested size, and finally arranges originals and additions together.

Newly selected songs do not change the mood board. If you start with soul and metal seeds, the first addition cannot pull the next search farther and farther toward an unrelated style. The original collection remains the reference throughout.

All original songs are retained, but their order may change. **Grow from these seeds** always optimizes the final order because arranging the enlarged collection is part of the workflow.

#### Options for Grow from these seeds

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Final playlist size | 3–500; default 25 | Exact target size; it must be greater than the number of original seeds. |
| Musical context window | 1–50; inherited from BlissMixer | Controls final route ordering only. Membership relevance always uses every original seed. |
| Learned-matrix blend | 0–100%; inherited | Controls both the complete-seed relevance model and final Adaptive route scoring. |
| Artist look-back | 0–10,000; inherited | Limits artist membership capacity and constrains the final route. Zero disables it. |
| Album look-back | 0–10,000; inherited | Limits album membership capacity and constrains the final route. Zero disables it. |
| Additional route-search attempts | 0–500; default 50 | Adds seeded starts when arranging the completed membership. |
| Variation | 0–100%; default 25 | Controls membership-sampling breadth and enables per-job final-route diversity. |
| Generation seed | 0–4,294,967,295; generated by default | Reproduces both membership sampling and final routing. |
| Last.fm artist weighting | Off by default | Enables similar-artist guidance during membership selection. |
| Last.fm artist probability | 1–100%; default 25 | Target share of additions from endorsed artists when both candidate groups exist. |
| Output | Create copy | Preview is read-only. Creating a verified copy works; source overwrite is planned. |

#### How new playlist members are selected

Seed growth separates two questions:

- **Which songs belong in this playlist?** Every original source song is used together as one immutable relevance context. The context-window setting does not truncate this set.
- **In which order should they play?** After membership is fixed, the normal route optimizer uses rolling preceding contexts.

Every eligible local candidate is scored in parallel against the same complete-source relevance model. Added tracks never become relevance seeds.

With both Variation and Last.fm probability at zero, the quality pool contains only as many top acoustic candidates as are requested. Otherwise it may contain up to ten times the requested additions, capped by the plugin’s current shortlist limit of 256 and by candidate availability.

With Variation above zero, candidates are reproducibly sampled without replacement. Better acoustic ranks receive exponentially higher weight; increasing Variation makes lower-ranked but still qualified candidates more likely. Last.fm-endorsed artists receive an additional weight aimed at the configured share. At zero Variation, Last.fm guidance remains deterministic and tries to fill that share from the acoustically ranked pool.

Membership selection also limits how many tracks from one artist or album may enter, based on the final target size and repeat windows. Tracks beyond the quality pool remain a deterministic feasibility fallback when better-ranked pool members cannot satisfy those capacities.

Once the exact target membership is complete, all originals and additions are passed to the standard route optimizer. Artist and album windows are then enforced on the final sequence.

~~~mermaid
flowchart TD
    A["All original tracks<br/>immutable relevance set"] --> B["One relevance model<br/>from the complete source set"]
    C["Every eligible local<br/>analyzed candidate"] --> D["Score against that same model"]
    B --> D
    D --> E["Acoustic rank and<br/>bounded quality pool"]
    L["Optional Last.fm<br/>artist evidence"] --> F
    E --> F["Reproducible membership selection<br/>using Variation and artist target"]
    F --> G["Apply artist and album<br/>membership capacities"]
    G --> H{"Exact target reached?"}
    H -- No --> X["Fail without partial output"]
    H -- Yes --> I["Fix complete membership"]
    I --> J["Optimize order with rolling<br/>preceding contexts"]
    J --> K["Prove target, sources, locality,<br/>uniqueness and repeat windows"]
~~~

## Similarity supplied by BlissMixer

Similarity scoring is an input to the playlist workflows above, not Better Call Bliss’s main feature. The algorithms and learned-matrix capability come from the [BlissMixer implementation and its algorithm guide](https://github.com/chrober/lms-blissmixer/blob/main/ALGORITHMS.md). Better Call Bliss depends on a compatible lms-blissmixer installation and reuses the shared native Bliss scoring core so both applications interpret the 23 Bliss audio features consistently.

Only **Adaptive dynamic weighting** is currently connected to Better Call Bliss, so it is the only similarity scorer with an applicable per-job option table. Static Weights and Extended Isolation Forest remain BlissMixer capabilities; their future Better Call Bliss entries are disabled, and listing hypothetical controls for them would make planned behavior look implemented.

### Adaptive dynamic weighting — working

Adaptive behaves like a DJ who listens for the common thread in the music immediately before the next song. If those songs share a rhythmic feel, rhythm becomes an important clue. If they instead share a similar tone or harmony, Adaptive follows that clue. The important qualities can change as the playlist develops.

**Musical context window** tells it how many previous songs to consider. A value of 3 means “judge the next song using up to the previous three songs.” Near the beginning, it uses the smaller context available.

#### Options for Adaptive scoring

| Option | Range / default | Effect |
| --- | --- | --- |
| Musical context window | 1–50; inherited from BlissMixer | Maximum preceding tracks used for each directional route or bridge score. Seed-growth membership deliberately uses all original seeds instead. |
| Learned-matrix blend | 0–100%; inherited | Learned share for contexts with at least two tracks. Zero means pure variance there; current one-track contexts still require and use the learned matrix. |

#### How Adaptive calculates distance

Each analyzed track has the same 23-feature Bliss vector: tempo, timbre, loudness, and chroma measurements.

For a non-empty context:

1. The optimizer calculates the arithmetic mean of the context vectors. This is the target sound.
2. With two or more context tracks, it derives a variance-based matrix. Features on which those tracks agree receive more influence; features on which they differ receive less.
3. It blends that matrix with the learned Mahalanobis matrix using **Learned-matrix blend**.
4. It calculates the Mahalanobis distance from the candidate vector to the context mean. Smaller means a closer fit.

With one context track, variance cannot be derived from the context. BlissMixer can fall back to its standard selection algorithm when no learned matrix is available. Better Call Bliss does not yet implement that fallback, so its native optimizer currently uses the learned matrix directly for a one-track context.

Distance is directional because the context comes from the proposed route prefix. A → B and B → A need not receive the same score.

#### Is a learned matrix optional?

For BlissMixer and the shared Adaptive algorithm, **yes**. A learned matrix is optional personalization produced by the similarity survey and training process:

- with two or more context tracks and no learned matrix, Adaptive can use the variance-based matrix by itself;
- with two or more context tracks and a learned matrix, **Learned-matrix blend** combines the learned and variance-based matrices;
- with one context track, no variance matrix can be calculated; BlissMixer can fall back to its standard algorithm when the learned matrix is absent.

For the **current Better Call Bliss build**, the file is nevertheless a runtime requirement. Every route begins with a first scored transition that has exactly one preceding track. The optimizer currently has no standard/static fallback for that one-track context, rejects an Adaptive request without the matrix, and loads and uses the matrix itself. It does not delegate playlist scoring to the running bliss-mixer service.

This also explains the perhaps surprising behavior of **Learned-matrix blend = 0**: multi-track contexts use pure variance weighting, but one-track contexts still use the learned matrix. The file can therefore still affect the result and must currently be present.

Making the file genuinely optional in Better Call Bliss requires a defined and tested one-track fallback—preferably matching BlissMixer’s standard/static behavior—plus optional matrix fields in the optimizer’s request and result artifacts. This is an implementation limitation, not a claim that users inherently need to train a personal matrix.

~~~mermaid
flowchart TD
    A["Take the applicable context tracks"] --> B["Read their 23-feature vectors"]
    B --> C["Calculate context mean"]
    B --> D{"How many context tracks?"}
    D -- One --> E["Use learned matrix<br/>(current Better Call Bliss requirement)"]
    D -- Two or more --> F["Calculate variance-based matrix"]
    F --> G["Blend learned matrix when supplied;<br/>otherwise use variance alone"]
    E --> H["Mahalanobis distance:<br/>candidate to context mean"]
    G --> H
    H --> I["Smaller contextual distance<br/>means a smoother fit"]
~~~

### Static weighted distance — planned for Better Call Bliss

Static mode lets BlissMixer users give permanent instructions such as “care a lot about rhythm, somewhat about tone, and less about harmony.” The same priorities apply to every selection.

A future Better Call Bliss integration would replace the adaptive matrix with a fixed job-local matrix derived from those priorities. The route search, bridge tests, repeat constraints, Variation, and result proofs could remain shared. Better Call Bliss does not yet have the native request contract or per-job controls for those weights, so the option is disabled.

### Extended Isolation Forest — planned for Better Call Bliss

Forest mode uses several example songs to learn the broad sound they share, then favors songs that fit that group and treats outsiders as less suitable.

Bringing it into playlist routing still requires decisions about the minimum context near the start of a route, fallback behavior, when to rebuild a model after a route change, and how to score both sides of a bridge. Better Call Bliss therefore disables it instead of silently substituting another scorer.

## Behavior shared across workflows

The workflow tables omit **Track look-back** because every current workflow already requires unique playlist membership. Its compatibility value is retained in requests and result proofs, but changing it cannot alter the generated playlist today.

### Variation and reproducibility

Variation asks Better Call Bliss to explore different qualified answers. It does not change Bliss features, similarity matrices, repeat windows, or bridge acceptance gates.

For movable routes, a generated or supplied seed changes the greedy restart paths. The percentage currently acts as an on/off switch for route diversity: zero uses a fixed baseline seed; any positive value uses the job’s generation seed.

For seed growth, the percentage additionally controls membership sampling inside the quality pool. Higher values flatten the acoustic weighting and make lower-ranked qualified candidates more likely.

Automatic and exact bridge selection is otherwise deterministic after the base source route has been chosen. Preserve-order jobs may return the same result at different seeds because their anchors cannot move.

A recorded generation seed reproduces the same request and result across worker counts when the library, artifacts, and options are unchanged.

### Last.fm artist guidance

Last.fm is an optional guide for choosing new songs. It never replaces Bliss similarity and never causes a non-local or otherwise invalid track to be admitted.

Better Call Bliss uses the installed LastMix plugin without user credentials. It requests similar artists once for every distinct artist in the complete original playlist and records endpoint-local and collection-fallback relationships.

For bridge modes, enabling Last.fm changes candidate-pool choice and ranking. The current bridge selector treats Last.fm evidence as a categorical priority; the numeric **Last.fm artist probability** does not scale that priority and is not a bridge quota.

For seed growth, the percentage is a target share of additions from endorsed artists when endorsed and non-endorsed candidates are both available. Last.fm has no effect on reorder-only membership.

Missing LastMix, no Internet access, malformed responses, and provider errors fall back to Bliss without failing the playlist job. Service-wide offline, unavailable, and rate-limit errors open a per-job circuit breaker so the remaining artists are not queried repeatedly.

### Safety and result proofs

Before you save anything, Better Call Bliss checks that the proposed playlist still contains what you asked for and that every addition is a real local Lyrion track.

A successful result proves the invariants relevant to its workflow:

- every original track is retained exactly once;
- preserved originals remain the same ordered subsequence;
- every addition belongs to the frozen current LMS-local inventory;
- membership is unique;
- requested exact or target counts are satisfied; and
- artist, album, and track-repeat rules hold.

Preview writes no playlist. Only the separate user-confirmed action invokes Lyrion’s playlist serializer and verifies the saved file and catalog order.
