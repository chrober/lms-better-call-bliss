# Mixing strategies and options

Better Call Bliss turns a saved playlist into a smoother listening experience. You choose what may change; Better Call Bliss previews the result; and nothing is saved until you accept it.

This document describes the current 0.13.0 implementation. **Working** means the choice is available in the Lyrion job editor. **Planned** means it is shown but cannot yet be selected.

## Choose the result you want

Three choices work together:

1. **Source-track order:** May Better Call Bliss move the songs already in the playlist?
2. **Additional tracks:** Should it use only those songs, repair a few transitions, add an exact number, or grow a small seed playlist?
3. **Mixing strategy:** What should “sounds good together” mean?

| If you want to… | Choose… | What happens |
| --- | --- | --- |
| Smooth out a shuffled collection without adding songs | Optimize source order + Reorder only | The same songs are rearranged. |
| Keep a carefully chosen order but soften awkward changes | Preserve source order + Add automatically | Original songs stay put; helpful songs may be inserted between them. |
| Make a playlist exactly N songs longer | Optimize or Preserve + Add exactly N tracks | Exactly N suitable local songs are inserted, or the job explains why it cannot do so. |
| Turn a tiny playlist into a full mix with the same general character | Grow from these seeds | Every original song stays; similar local songs are selected until the target size is reached; then the complete set is arranged. |
| Get a different but still sensible result | Increase Variation | Search explores different good alternatives without relaxing the safety rules. |
| Favor artists related to the original artists | Enable Last.fm artist weighting | Last.fm guides selection when songs are added; Bliss remains the acoustic quality check. |

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
| Adaptive dynamic weighting | Working | Let the music itself determine which sound qualities matter. |
| Static weighted distance | Planned | Let the user set fixed priorities such as rhythm versus harmony. |
| Random forest | Planned | Find songs that fit the overall sound shared by a larger group of examples. |

# What the choices mean in plain English

## Mixing strategy: how songs are judged

### Adaptive dynamic weighting — working

Think of Adaptive as a DJ who listens for the common thread in the music heard just before the next song. If those songs share a rhythmic feel, rhythm becomes an important clue. If they instead share a similar tone or harmony, Adaptive follows that clue. It can change its mind as the playlist develops, so one part of the playlist may be joined by rhythm and another by atmosphere.

The **Musical context window** tells the DJ how much recent music to remember. A value of 3 means “judge the next song using up to the previous three songs.” Near the beginning, fewer songs are available, so it simply uses what is there.

The optional learned model represents preferences gathered from your similarity survey. **Learned-matrix blend** controls how strongly that personal taste influences Adaptive’s reading of the current music.

### Static weighted distance — planned

Static mode would let you give the DJ permanent instructions such as “care a lot about rhythm, somewhat about tone, and less about harmony.” The same instructions would apply from the first song to the last. This is useful when you already know what kind of continuity you want, but it is not connected yet.

### Random forest — planned

Forest mode would listen to a larger group of example songs and learn the broad shape they share. It would then prefer songs that belong naturally to that group and reject songs that feel like outsiders. This can suit a broad but coherent set of seeds, but it is not connected yet.

## Playlist workflows: what happens to the playlist

### Reorder existing tracks only

Imagine writing every song on a card and asking a DJ to lay out all the cards. No card may be removed or duplicated, and no new card may be added. The DJ tries many arrangements and keeps one whose handovers feel smooth, paying extra attention to avoiding one especially unpleasant jump.

The result may start with any song. It may also build gently toward a livelier section and ease back afterward, but only when that shape does not noticeably damage the musical transitions.

### Add automatically

Better Call Bliss first decides the order of the original songs—or respects your order if you chose Preserve. It then listens to each handover and asks: “Is this one of the awkward changes, and can one extra song genuinely improve it?”

Suppose the playlist contains A followed by B. A candidate C is used only if A → C and C → B both work. It is not enough for C to resemble only A or only B. If the original transition is already fine, or no candidate improves it safely, nothing is inserted. Therefore “Add automatically” can correctly add zero songs.

### Add exactly N tracks

This asks for a result of a specific size. Better Call Bliss considers different gaps and combinations instead of simply filling the first N gaps. It succeeds only when it can place all N songs while keeping every transition and repeat rule acceptable. Otherwise it returns an explanation rather than quietly producing fewer additions.

The current plugin can add at most one song between each pair of original songs. It does not add a song before the first or after the last original song.

### Preserve source order and fill gaps

Your original songs become fixed stepping stones. Better Call Bliss may place new stones between them, but it cannot swap or move the originals.

For example, A → B → C can become A → X → B → Y → C, but never B → A → C. This is useful for chronological playlists, albums, stories, or any sequence whose order already matters to you.

Preserve plus “Reorder only” would leave the playlist unchanged, so that combination is rejected.

### Grow from these seeds

This is for a small playlist that says “more music like this.” Every original song acts as part of one musical mood board. Better Call Bliss searches the analyzed songs in your local Lyrion library for tracks that fit that complete mood board, selects enough to reach the requested size, and finally arranges originals and additions together.

Newly selected songs do not change the mood board. If you start with soul and metal seeds, the first addition cannot pull the next search farther and farther toward an unrelated style. The original collection remains the reference throughout.

All original songs are retained, but their order may change. “Grow from these seeds” always optimizes the final order because arranging the enlarged collection is part of the workflow.

# Technical reference

## Components and responsibility

The plugin resolves Lyrion tracks, reads per-job options, freezes the LMS-local candidate inventory, and optionally asks LastMix for Last.fm artist relationships. The native [bliss-playlist-optimizer](https://github.com/chrober/bliss-playlist-optimizer) performs scoring and bounded search. Only the plugin writes a playlist, and only after the user accepts a completed Preview.

~~~mermaid
flowchart TD
    P["Saved Lyrion playlist<br/>original source tracks"] --> O["Per-job ordering,<br/>extension, scoring,<br/>repeat and variation options"]
    DB[("bliss.db<br/>23 features per analyzed track")] --> I["Intersect Bliss rows with<br/>current local LMS library"]
    M["learned_matrix.json"] --> N
    O --> N["Native optimizer request"]
    I --> N
    L["Optional LastMix<br/>artist relationships"] --> N
    N --> S["Choose source route<br/>or preserve anchors"]
    S --> X{"Extension mode"}
    X -- None --> R["Final route"]
    X -- Automatic or exact --> B["Gap-specific bridge search"]
    X -- Seed growth --> G["Full-source relevance selection<br/>then final route search"]
    B --> R
    G --> R
    R --> V["Result artifact and proofs"]
    V --> Q["Read-only Preview"]
    Q -->|"user accepts"| W["Lyrion playlist writer"]
~~~

## The core answer to “similar to which tracks?”

The answer depends on the operation:

| Decision being scored | Tracks used as the similarity context | Track being compared with that context |
| --- | --- | --- |
| Place the next song while reordering | Up to N immediately preceding songs in that proposed route | Each unused source song |
| Score an existing transition A → B | Up to N preceding route songs, ending with A | B |
| Test the first half of bridge A → C → B | Up to N preceding route songs, ending with A | Candidate C |
| Test the second half of bridge A → C → B | Up to N preceding route songs after inserting C, ending with C | B |
| Select membership for Grow from these seeds | Every original source song, regardless of its order | Every eligible local candidate |
| Arrange the completed seed-growth membership | Up to N immediately preceding songs in each proposed final route | Each possible next song |

Here, N is **Musical context window**. The context is directional and normally contains only preceding songs. A future destination does not enter the context early. For a bridge, however, the destination B is still explicitly tested as the second leg after C is inserted.

Example with a context window of 3:

~~~mermaid
flowchart LR
    P["… W → X → A"] --> C["candidate C"]
    C --> B["original B"]
    L["Score A-side:<br/>context W, X, A<br/>candidate C"] -.-> C
    R["Score B-side:<br/>context X, A, C<br/>candidate B"] -.-> B
~~~

The earliest item W falls out of the second context because the window still contains at most three tracks. This is why C → B is not a simple pairwise comparison and why the score for a transition can change when earlier songs move or bridges are inserted.

## Adaptive distance calculation

Each analyzed track has the same 23-feature Bliss vector: tempo, timbre, loudness, and chroma measurements.

For a non-empty context:

1. The optimizer takes the arithmetic mean of the context vectors. This is the target sound.
2. With two or more context tracks, it derives a variance-based matrix. Features on which those tracks agree receive more influence; features on which they differ receive less.
3. It blends that matrix with the learned Mahalanobis matrix using **Learned-matrix blend**.
4. It calculates the Mahalanobis distance from the candidate vector to the context mean. Smaller is considered more similar.

With one context track, variance cannot be learned from the context, so the learned matrix is used directly. The current plugin requires the learned-matrix file even when the multi-track blend is set to zero.

Because the context depends on the proposed route prefix, distance is directional. A → B and B → A need not receive the same score.

~~~mermaid
flowchart TD
    A["Take the applicable context tracks"] --> B["Read their 23-feature vectors"]
    B --> C["Calculate context mean"]
    B --> D{"How many context tracks?"}
    D -- One --> E["Use learned matrix"]
    D -- Two or more --> F["Calculate variance-based matrix"]
    F --> G["Blend variance and learned matrices"]
    E --> H["Mahalanobis distance:<br/>candidate to context mean"]
    G --> H
    H --> I["Smaller contextual distance<br/>means a smoother fit"]
~~~

### Planned scorer boundaries

**Static weighted distance** is intended to replace the adaptive matrix above with one fixed job-local matrix derived from user priorities for tempo, timbre, loudness, and chroma. The context target would still be the mean of the applicable tracks, and route search, bridge tests, repeat constraints, Variation, and output proofs could remain shared. The native request contract and plugin controls for those fixed weights do not exist yet, so details beyond that boundary are not promises of current behavior.

**Random forest** is intended to fit a context model from several applicable tracks and score a candidate by how well it belongs to that distribution rather than by Mahalanobis distance to a mean. Minimum context size, fallback behavior near the start of a route, model lifetime while a route changes, and bridge-leg scoring still need design work. It is therefore disabled rather than silently falling back to another scorer.

## Reorder-only route search

For every proposed route position after the first, the transition score uses the preceding-context rule above. The first track has no incoming transition and therefore no similarity score.

The search evaluates:

- the original order;
- the reverse order;
- for the energy-aware search, an intensity-sorted start; and
- the configured number of seeded greedy restarts.

A greedy restart chooses a random first song. At each following position it scores every repeat-feasible unused song against the current preceding context, ranks them, and makes a seeded choice among the best four with a strong bias toward the best. Each completed start is repeatedly improved by reversing a section or relocating one song. Every affected contextual transition is then scored again.

Artist and album windows are hard constraints. A route that violates either is not accepted. Track repetition cannot occur because each fixed member appears exactly once.

The primary route objective is:

    sum of all transition distances + 2 × the worst transition

The extra penalty makes one severe jump more costly than its contribution to the sum alone.

In parallel, an energy-aware search favors a broad rise from approximately 0.25 intensity to 0.85 near 70% of the playlist, then a fall toward approximately 0.35. Intensity is a rank-based composite of five Bliss features. The energy-aware route replaces the primary route only if:

- its primary objective is no more than 8% worse; and
- its energy-arc error is at least 10% better.

~~~mermaid
flowchart TD
    A["Fixed playlist membership"] --> B["Original, reverse and<br/>seeded greedy starts"]
    B --> C["At each position, compare every<br/>unused song with the preceding context"]
    C --> D["Reverse sections and relocate songs<br/>until no local move improves the route"]
    D --> E{"Artist and album<br/>windows satisfied?"}
    E -- No --> X["Reject attempt"]
    E -- Yes --> F["Measure total distance<br/>and worst transition"]
    F --> G["Best primary route"]
    B --> H["Parallel energy-aware search"]
    H --> I{"Within 8% primary cost<br/>and at least 10% better arc?"}
    I -- Yes --> J["Use energy-aware route"]
    I -- No --> G
~~~

## Candidate inventory shared by all addition modes

Before any new song is considered, the plugin intersects usable rows in bliss.db with current, local LMS tracks. This excludes stale or non-LMS Bliss rows. The optimizer then excludes:

- every source file already in the playlist; and
- another file with the same normalized artist-and-title identity as a source.

The remaining analyzed local tracks are the eligible candidate inventory. Uniqueness and repeat checks are applied again during search and before persistence.

## Bridge search: automatic and exact additions

### 1. Establish a stable quality scale

Raw adaptive distances differ between contexts, so bridge mode first builds a frozen reference distribution. For every position in the selected source route, it scores the original source tracks that are not part of that position’s context against that context. The sorted collection of those source-to-context distances becomes the job’s scale.

A percentile therefore means “how this distance compares with many contextual alternatives drawn from the original source collection,” not “percentage similarity” and not a percentile over the entire music library. The scale is frozen before any bridge is inserted, allowing all gaps and candidates to be compared consistently.

### 2. Choose candidates for a particular gap

For an original gap A → B, Last.fm guidance is applied in this order:

1. **Endpoint-local:** candidates whose artists Last.fm reports as similar to A’s or B’s artist.
2. **Collection fallback:** used only when endpoint-local produces no candidate; candidates may relate to any artist in the complete original playlist.
3. **Bliss only:** used when neither Last.fm pool produces a candidate.

The plugin asks LastMix about every distinct artist in the original playlist. Current Last.fm evidence is artist-level only. The native evidence contract also supports recording-level evidence for future providers.

If the chosen pool exceeds 256 candidates, up to 32 highest-priority semantic candidates are reserved and the remaining shortlist slots are filled by acoustic two-leg rank. The candidate list and semantic evidence are then frozen for that original gap.

### 3. Test both sides of every candidate

For C inserted between A and B:

- **Left leg:** compare C with the preceding context ending in A.
- **Right leg:** insert C, then compare B with the updated preceding context ending in C.

Both leg distances are converted to frozen-reference percentiles. C is admissible only when:

- it is not already in the route;
- the full tentative route satisfies artist and album windows;
- the worse leg is at or below percentile 0.70; and
- the two leg percentiles sum to at most 1.30.

Accepted candidates rank by semantic evidence first, then by the better worst leg, then by the smaller two-leg sum, with a stable identity tie-break. These fixed native gates are not currently exposed as job controls.

### 4a. Automatic selection

An original gap is considered only when its direct distance is above **Bridge trigger percentile**. Gaps are processed from left to right. Bridges selected for earlier gaps become part of the preceding context when later candidates are scored.

The first accepted candidate is inserted only if its local objective is better than the direct gap:

    (left distance + right distance) + 2 × max(left distance, right distance)
        < direct distance + 2 × direct distance

Processing stops at **Maximum additional tracks**. A gap below the trigger, a depleted budget, a repeat conflict, failed acoustic gates, or no genuine improvement leaves that gap unchanged.

### 4b. Exact-count selection

Exact mode does not use the automatic trigger. For each gap, it branches into “skip” and the best admissible candidate choices, re-evaluates the complete route objective, groups states by their current addition count, and retains the best bounded set. The current native beam width is 64 and the plugin exposes up to five retained candidate alternatives per gap to that search.

The current plugin requests one bridge at most per internal original gap and disables opening and closing slots. With S source songs, the UI therefore allows no more than S − 1 additions. The native engine already has bounded multi-track-gap and endpoint support, but those controls are not connected.

~~~mermaid
flowchart TD
    A["Selected or preserved source route"] --> B["Build frozen source-based<br/>distance distribution"]
    B --> C["For gap A → B, choose<br/>endpoint-local, collection fallback,<br/>or Bliss-only candidate pool"]
    C --> D["Shortlist at most 256 candidates"]
    D --> E["Score context-ending-A → C"]
    E --> F["Insert C into context<br/>and score → B"]
    F --> G{"Unique, repeat-safe and<br/>both acoustic gates pass?"}
    G -- No --> H["Reject C"]
    G -- Yes --> I["Rank admissible candidate"]
    I --> J{"Automatic or exact?"}
    J -- Automatic --> K["Require difficult direct gap<br/>and genuine local improvement"]
    J -- Exact --> L["Explore skip/insert combinations<br/>and keep best exact-count route"]
~~~

## Preserve-order technical behavior

With **Preserve source order**, the input sequence is used directly as the source route. It is scored but not searched. The source anchors must already satisfy the requested repeat windows. The current pre-check rejects an existing anchor conflict before trying insertions, even though a future implementation could attempt to separate those anchors with added tracks; today such a job fails with a preserved-anchor conflict.

Bridge candidates are selected as described above. The final result must prove that filtering the final sequence down to original tracks yields the exact input sequence. Route-search restarts have no effect because the anchors cannot move.

## Seed-growth selection and routing

Seed growth is membership selection followed by ordinary route optimization:

1. **Immutable relevance context:** all original source tracks are used together. The context window does not truncate this set. Their mean and adaptive matrix define one job-wide relevance model.
2. **Full local scoring:** every eligible local candidate is scored against that same model in parallel. Added tracks never become relevance seeds.
3. **Quality pool:** with both Variation and Last.fm probability at zero, the pool contains only as many top acoustic candidates as are requested. Otherwise it can contain up to ten times the requested additions, capped by the plugin’s current shortlist limit of 256 and by availability.
4. **Variation and Last.fm:** with Variation above zero, candidates are reproducibly sampled without replacement. Better acoustic ranks get exponentially higher weight; Variation controls how quickly that weight falls. Last.fm-endorsed artists receive an additional weight aimed at the configured share. At zero Variation, Last.fm guidance remains deterministic and tries to fill the requested share from the acoustically ranked pool.
5. **Repeat capacity:** membership selection limits how many tracks from one artist or album may enter, based on the final target size and repeat windows. Candidates outside the quality pool remain a deterministic feasibility fallback only when better-ranked pool members cannot satisfy those capacities.
6. **Final route:** the fixed set of all sources plus selected additions is passed to the normal adaptive route optimizer. At this stage, similarity uses the rolling preceding context window, and artist and album windows are enforced exactly.

The relevance context uses all source tracks because they jointly define “more like this.” The final routing context uses only recent preceding tracks because it defines “what should play next.” These are deliberately different questions.

~~~mermaid
flowchart TD
    A["All original tracks<br/>immutable relevance seeds"] --> B["One mean and Adaptive matrix<br/>from the complete seed set"]
    C["Every eligible local<br/>analyzed candidate"] --> D["Score against the same<br/>complete-seed model"]
    B --> D
    D --> E["Acoustic rank and<br/>bounded quality pool"]
    L["Optional Last.fm artist evidence"] --> F
    E --> F["Reproducible membership selection<br/>using Variation and artist target"]
    F --> G["Apply artist and album<br/>membership capacities"]
    G --> H{"Exact target reached?"}
    H -- No --> X["Fail without partial output"]
    H -- Yes --> I["Fix complete membership"]
    I --> J["Optimize order using rolling<br/>preceding contexts"]
    J --> K["Prove target, sources, locality,<br/>uniqueness and repeat windows"]
~~~

## Variation and reproducibility

Variation does not alter Bliss features, distance matrices, repeat windows, or bridge acceptance gates.

- For movable routes, a generated or supplied seed changes the greedy restart paths. The variation percentage currently acts as an on/off switch for using the per-job seed: zero uses a fixed baseline seed; any positive value uses the job’s generation seed.
- For seed growth, the percentage also controls membership sampling inside the quality pool. Higher values flatten the acoustic weighting and make lower-ranked but still qualified candidates more likely.
- Automatic and exact bridge membership is otherwise deterministic after the base source route has been chosen.
- Preserve-order jobs may return the same result at different seeds because their anchors cannot move.

A recorded generation seed reproduces the same request and result across worker counts when the library, artifacts, and options are unchanged.

## Last.fm artist guidance and failure behavior

Last.fm is optional and is accessed through the installed LastMix plugin without user credentials. Better Call Bliss requests similar artists once for every distinct artist in the complete original playlist and records both endpoint-local and collection-fallback relationships.

For bridge modes, enabling Last.fm changes candidate-pool choice and ranking. The current bridge selector treats Last.fm evidence as a categorical priority; the numeric **Last.fm artist probability** does not scale that priority and is not a bridge quota. For seed growth, the percentage is a target share of additions from endorsed artists when both endorsed and non-endorsed candidates are available. Last.fm has no effect on reorder-only membership.

Last.fm never bypasses local-library membership, Bliss acoustic gates, uniqueness, or repeat windows. Missing LastMix, no Internet access, malformed responses, and provider errors fall back to Bliss without failing the playlist job. Service-wide offline, unavailable, and rate-limit errors open a per-job circuit breaker so the remaining artists are not queried repeatedly.

## Per-job options

Defaults are copied from BlissMixer or Better Call Bliss settings when the editor opens. Changing a job does not change global BlissMixer preferences.

| Option | Range / default | Exact effect |
| --- | --- | --- |
| Source-track order | Optimize by default | Optimize searches movable source routes. Preserve fixes originals as anchors. Seed growth always optimizes. |
| Additional tracks | None by default | Selects reorder-only, automatic bridges, exact-count bridges, or seed growth. |
| Musical context window | 1–50; inherited from BlissMixer | Maximum preceding tracks per route or bridge leg. Seed-growth relevance is the exception: it always uses all originals. |
| Learned-matrix blend | 0–100%; inherited | Learned share of the matrix for contexts of at least two tracks. A one-track context uses the learned matrix directly. |
| Artist look-back | 0–10,000; inherited | Forbids the same non-empty normalized artist key within that many preceding positions. Zero disables it. |
| Album look-back | 0–10,000; inherited | Forbids the same non-empty normalized album key within that many preceding positions. Zero disables it. |
| Track look-back | 0–10,000; inherited | Retained in the request and proofs. Current routes already require unique membership. |
| Additional route-search attempts | 0–500; default 50 | Adds seeded greedy starts for movable route search. Zero still evaluates built-in starts. |
| Variation | 0–100%; default 25 | Enables per-job route-seed diversity; in seed growth it also controls membership-sampling breadth. It does not weaken gates. |
| Generation seed | 0–4,294,967,295; blank by default | Blank generates a seed from the job identity. Reusing a reported seed reproduces the job. |
| Last.fm artist weighting | Off by default | Uses LastMix artist relationships only when tracks may be added. |
| Last.fm artist probability | 1–100%; default 25 | Seed-growth endorsed-artist target. The current bridge selector does not use the numeric percentage; enabling Last.fm gives matching bridge candidates categorical semantic priority. |
| Maximum additional tracks | 0–100; default 8 | Automatic-mode budget. Zero is rejected with Preserve because it guarantees no change. |
| Bridge trigger percentile | 0–100%; default 70 | Automatic mode considers only source gaps worse than this position in the frozen source-based distribution. |
| Exact number of additions | 1–100; default 1 | Required total, additionally limited by the current UI to S − 1 internal slots. |
| Final playlist size | 3–500; default 25 | Seed-growth target; it must exceed the source size. |
| Output | Create copy | Preview is always read-only. Creating a verified copy works; source overwrite is planned and unavailable. |

## Safety and result proofs

A successful result proves the invariants relevant to its workflow:

- every original track is retained exactly once;
- preserved originals remain the same ordered subsequence;
- every addition belongs to the frozen current LMS-local inventory;
- membership is unique;
- requested exact or target counts are satisfied; and
- artist, album, and track-repeat rules hold.

Preview writes no playlist. Only the separate user-confirmed action invokes Lyrion’s playlist serializer and verifies the saved file and catalog order.
