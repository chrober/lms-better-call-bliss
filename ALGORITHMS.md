# Playlist optimization modes and options

Better Call Bliss turns a saved playlist into a smoother listening experience. You decide whether existing songs may move, whether new songs may be added, and how much freedom the optimizer has. Better Call Bliss previews the result, and nothing is saved until you accept it.

This document describes the current 0.14.3 implementation. **Working** means the choice is available in the Lyrion job editor. **Planned** means it is shown but cannot yet be selected.

## Choose the result you want

| If you want toÃ¢â‚¬Â¦ | ChooseÃ¢â‚¬Â¦ | What happens |
| --- | --- | --- |
| Smooth out a shuffled collection without adding songs | [Optimize source order + Reorder only](#reorder-existing-tracks-only) | The same songs are rearranged. |
| Keep a carefully chosen order but soften awkward changes | [Preserve source order](#preserve-source-order-and-fill-gaps) + [Add automatically](#add-automatically) | Original songs stay put; helpful songs may be inserted between them. |
| Make a playlist exactly N songs longer | Optimize or [Preserve](#preserve-source-order-and-fill-gaps) + [Add exactly N tracks](#add-exactly-n-tracks) | Exactly N suitable local songs are inserted, or the job explains why it cannot do so. |
| Turn a tiny playlist into a full mix with the same general character | [Grow from these seeds](#grow-from-these-seeds) | Every original song stays; similar local songs are selected until the target size is reached; then the complete set is arranged. |
| Get a different but still sensible result | [Increase Variation](#variation-and-reproducibility) | Search explores different good alternatives without relaxing its quality and repeat rules. |
| Let related recordings and artists support addition choices | [Enable Last.fm guidance](#lastfm-track-and-artist-guidance) | Similar-track and similar-artist evidence help rank suitable additions; Bliss remains the acoustic quality check. |

Three job choices work together:

1. **Source-track order** decides whether songs already in the playlist may move.
2. **Additional tracks** decides whether the playlist keeps its membership, repairs selected gaps, gains an exact number of songs, or grows from a seed collection.
3. **Mixing strategy** supplies the similarity measurement used by those playlist operations. Better Call Bliss reuses this capability from BlissMixer; it is not the main feature being selected here.

## Features at a glance

| Choice | Status | Listener-facing result |
| --- | --- | --- |
| [Optimize source order](#reorder-existing-tracks-only) | Working | Rearrange the original songs into a smoother sequence. |
| [Preserve source order and fill gaps](#preserve-source-order-and-fill-gaps) | Working | Keep the originals in their chosen order and insert help between them. |
| [Reorder existing tracks only](#reorder-existing-tracks-only) | Working | Change the order, not the contents. |
| [Add automatically](#add-automatically) | Working | Repair only transitions that need it, up to a limit. |
| [Add exactly N tracks](#add-exactly-n-tracks) | Working | Add the requested number or return no partial result. |
| [Grow from these seeds](#grow-from-these-seeds) | Working | Use all originals as a musical mood board and build a larger playlist around them. |
| [One bridge per transition](#add-exactly-n-tracks) | Planned | Put one additional song in every gap. |
| [Reach target length / double length](#add-exactly-n-tracks) | Planned | Convenience presets that calculate how many songs to add. |
| [Adaptive dynamic weighting](#adaptive-dynamic-weighting--working) | Working | Use BlissMixerÃ¢â‚¬â„¢s adaptive similarity measurement for each decision. |
| [Static weighted distance](#static-weighted-distance--working) | Working | Reuse BlissMixer's fixed user priorities. |
| [Extended Isolation Forest](#extended-isolation-forest--planned-for-better-call-bliss) | Planned | Reuse BlissMixer's model of the sound shared by several example songs. |

## How the pieces fit together

The Better Call Bliss plugin resolves Lyrion tracks, reads per-job options, freezes the LMS-local candidate inventory, and optionally asks LastMix for Last.fm track and artist relationships. The native [bliss-playlist-optimizer](https://github.com/chrober/bliss-playlist-optimizer) performs scoring and bounded search. Only the plugin writes a playlist, and only after the user accepts a completed Preview.

~~~mermaid
flowchart TD
    P["Saved Lyrion playlist<br/>original source tracks"] --> O["Per-job ordering,<br/>extension, scoring,<br/>repeat and variation options"]
    DB[("bliss.db<br/>23 features per analyzed track")] --> I["Intersect Bliss rows with<br/>current local LMS library"]
    M["optional learned_matrix.json<br/>personalized Adaptive blend"] --> N
    O --> N["Native optimizer request"]
    I --> N
    L["Optional LastMix<br/>track and artist relationships"] --> N
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
| Musical context window | 1Ã¢â‚¬â€œ50; inherited from BlissMixer | Maximum number of immediately preceding route tracks used to judge each possible next song. |
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0Ã¢â‚¬â€œ10,000; inherited | Forbids the same artist within that many preceding positions. Zero disables it. |
| Album look-back | 0Ã¢â‚¬â€œ10,000; inherited | Forbids the same album within that many preceding positions. Zero disables it. |
| Additional route-search attempts | 0Ã¢â‚¬â€œ500; default 50 | Adds seeded greedy starting routes. Zero still evaluates the built-in starts. |
| Variation | 0Ã¢â‚¬â€œ100%; default 25 | Zero uses a fixed baseline route seed; any positive value uses the jobÃ¢â‚¬â„¢s generation seed. |
| Generation seed | 0Ã¢â‚¬â€œ4,294,967,295; generated by default | When Variation is positive, reusing the reported seed reproduces the same search. |
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

    sum of all transition distances + 2 Ãƒâ€” the worst transition

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

For example, A Ã¢â€ â€™ B Ã¢â€ â€™ C can become A Ã¢â€ â€™ X Ã¢â€ â€™ B Ã¢â€ â€™ Y Ã¢â€ â€™ C, but never B Ã¢â€ â€™ A Ã¢â€ â€™ C. This is useful for chronological playlists, albums, stories, or any sequence whose order already matters to you.

#### Options for Preserve source order

Preserve is an ordering policy used with **Add automatically** or **Add exactly N tracks**. The chosen addition workflow supplies its remaining controls.

| Option | Range / default | Effect with preserved anchors |
| --- | --- | --- |
| Source-track order | Preserve | Keeps every original track as an immutable ordered anchor. |
| Musical context window | 1Ã¢â‚¬â€œ50; inherited from BlissMixer | Controls the preceding context used for direct gaps and both legs of an inserted bridge. |
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0Ã¢â‚¬â€œ10,000; inherited | Applied to the source-anchor pre-check and final route. Zero disables it. |
| Album look-back | 0Ã¢â‚¬â€œ10,000; inherited | Applied to the source-anchor pre-check and final route. Zero disables it. |
| Use Last.fm guidance | Inherited; optional | Asks LastMix for track and artist relationships. Failures transparently use Bliss alone. |
| Similar-track guidance | 0Ã¢â‚¬â€œ100%; default 75 | Bounded influence of recording-level evidence from the neighboring source tracks. Zero ignores it. |
| Similar-artist guidance | 0Ã¢â‚¬â€œ100%; default 75 | Bounded influence of endpoint-local artist evidence, with the complete original artist set as fallback. Zero ignores it. |
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

Better Call Bliss first decides the order of the original songsÃ¢â‚¬â€or respects your order if you chose Preserve. It then listens to each handover and asks: Ã¢â‚¬Å“Is this one of the awkward changes, and can one extra song genuinely improve it?Ã¢â‚¬Â

Suppose the playlist contains A followed by B. A candidate C is used only if A Ã¢â€ â€™ C and C Ã¢â€ â€™ B both work. It is not enough for C to resemble only A or only B. If the original transition is already fine, or no candidate improves it safely, nothing is inserted. Therefore **Add automatically** can correctly add zero songs.

#### Options for Add automatically

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Source-track order | Optimize by default | Either optimizes the originals before gap repair or preserves them as anchors. |
| Musical context window | 1Ã¢â‚¬â€œ50; inherited from BlissMixer | Controls the preceding context for direct gaps and both candidate legs. |
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0Ã¢â‚¬â€œ10,000; inherited | Rejects tentative and final routes with artists too close together. Zero disables it. |
| Album look-back | 0Ã¢â‚¬â€œ10,000; inherited | Rejects tentative and final routes with albums too close together. Zero disables it. |
| Additional route-search attempts | 0Ã¢â‚¬â€œ500; default 50 | Applies only when source order is Optimize. |
| Variation | 0Ã¢â‚¬â€œ100%; default 25 | Can vary the optimized source route; it has no separate random bridge-selection step. |
| Generation seed | 0Ã¢â‚¬â€œ4,294,967,295; generated by default | Reproduces the optimized source route when source order may move. |
| Use Last.fm guidance | Inherited; optional | Enables failure-tolerant track and artist evidence through LastMix. |
| Similar-track guidance | 0Ã¢â‚¬â€œ100%; default 75 | Bounded support from tracks related to A, B, or both. Zero ignores recording evidence. |
| Similar-artist guidance | 0Ã¢â‚¬â€œ100%; default 75 | Bounded support from related endpoint artists or, when no local evidence exists, the original artist collection. Zero ignores artist evidence. |
| Maximum additional tracks | 0Ã¢â‚¬â€œ100; default 8 | Stops insertion after this many bridges. |
| Bridge trigger percentile | 0Ã¢â‚¬â€œ100%; default 70 | Considers only original gaps above this point on the frozen reference scale. |
| Output | Create copy | Preview is read-only. Creating a verified copy works; source overwrite is planned. |

#### How difficult gaps are recognized

Raw similarity distances from different parts of a playlist are not directly comparable because their preceding contexts differ. For a direct transition A Ã¢â€ â€™ B, B is compared with up to **Musical context window** preceding songs ending in A. Better Call Bliss therefore builds one frozen reference distribution before adding anything.

At every position in the selected source route, it scores original source songs that are not in that positionÃ¢â‚¬â„¢s context against that context. The sorted source-to-context distances become the jobÃ¢â‚¬â„¢s scale. A percentile means Ã¢â‚¬Å“how this distance compares with many alternatives drawn from the original playlist.Ã¢â‚¬Â It is not percentage similarity, and the reference is not built from the complete music library.

An original gap is eligible only when its direct distance is above **Bridge trigger percentile**.

#### How candidates are chosen for one gap

For a gap A Ã¢â€ â€™ B, optional Last.fm evidence has this order of strength:

1. **Track-similar to both A and B:** recording evidence agrees on both sides of the gap.
2. **Track-similar to A or B:** one neighboring recording endorses the candidate.
3. **Endpoint-local similar artist:** Last.fm relates the candidateÃ¢â‚¬â„¢s artist to AÃ¢â‚¬â„¢s or BÃ¢â‚¬â„¢s artist.
4. **Collection artist fallback:** used only when the gap has no endpoint-local track or artist evidence; the candidateÃ¢â‚¬â„¢s artist may relate to any artist in the complete original playlist.
5. **Bliss only:** a candidate without Last.fm evidence remains eligible.

The plugin asks LastMix about every distinct track and artist in the original playlist, using anonymous `track.getSimilar` and `artist.getSimilar` access, and retains at most the first 25 valid results from each request. A source recordingÃ¢â‚¬â„¢s Lyrion MBID is used for the LastMix request when available, with LastMix falling back to artist and title. Returned recordings currently resolve to analyzed local candidates by normalized artist and title; their returned MBIDs are also retained in the frozen evidence. Last.fmÃ¢â‚¬â„¢s match score, rank, identity confidence, and the exact source relationship are frozen with them.

Last.fm never replaces the candidate library. Every candidate still comes from the frozen intersection of usable Bliss rows and current local LMS tracks. If the pool contains more than 256 tracks, up to 32 strongest semantic matches are reserved while acoustic shortlisting fills the remaining positions. Bliss then evaluates both legs, repeat safety, and improvement. Rejected candidates stay rejected regardless of Last.fm evidence.

Among candidates that pass those checks, the two job percentages provide a bounded ranking adjustment. Evidence strength uses Last.fmÃ¢â‚¬â„¢s match score when present, otherwise its result rank, and is reduced for uncertain identity matches. Support from both recordings is stronger than support from one; collection-level artist evidence is weaker than endpoint-local artist evidence. The combined adjustment is capped at ten percentile points. Therefore 100% means maximum permitted guidance, not Ã¢â‚¬Å“let Last.fm choose,Ã¢â‚¬Â while 0% completely ignores that evidence type.

#### How a bridge is tested

For C inserted between A and B:

- **Left leg:** compare C with up to N preceding tracks ending in A.
- **Right leg:** insert C, then compare B with the updated preceding context ending in C.

N is **Musical context window**. With N = 3 and a route ending W Ã¢â€ â€™ X Ã¢â€ â€™ A Ã¢â€ â€™ B, the left context is W, X, A and the candidate is C. For the second leg the context becomes X, A, C and the candidate is B. W drops out of the window.

~~~mermaid
flowchart LR
    P["Ã¢â‚¬Â¦ W Ã¢â€ â€™ X Ã¢â€ â€™ A"] --> C["candidate C"]
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

    (left distance + right distance) + 2 Ãƒâ€” max(left distance, right distance)
        < direct distance + 2 Ãƒâ€” direct distance

Processing stops at **Maximum additional tracks**. A gap below the trigger, a depleted budget, a repeat conflict, failed acoustic gates, or no genuine improvement remains unchanged.

~~~mermaid
flowchart TD
    A["Selected or preserved source route"] --> B["Build frozen source-based<br/>distance distribution"]
    B --> C["Inspect original gaps<br/>from left to right"]
    C --> D{"Direct gap above trigger?"}
    D -- No --> N["Leave gap unchanged"]
    D -- Yes --> E["Choose endpoint-local,<br/>collection fallback or<br/>Bliss-only pool"]
    E --> F["Shortlist at most 256 tracks"]
    F --> G["Score context-ending-A Ã¢â€ â€™ C"]
    G --> H["Insert C into context<br/>and score Ã¢â€ â€™ B"]
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
| Musical context window | 1Ã¢â‚¬â€œ50; inherited from BlissMixer | Controls both contextual legs of every candidate insertion and final route scoring. |
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0Ã¢â‚¬â€œ10,000; inherited | Rejects candidate combinations and final routes with artists too close together. Zero disables it. |
| Album look-back | 0Ã¢â‚¬â€œ10,000; inherited | Rejects candidate combinations and final routes with albums too close together. Zero disables it. |
| Additional route-search attempts | 0Ã¢â‚¬â€œ500; default 50 | Applies only when source order is Optimize. |
| Variation | 0Ã¢â‚¬â€œ100%; default 25 | Can vary the optimized source route; exact bridge combination search remains deterministic afterward. |
| Generation seed | 0Ã¢â‚¬â€œ4,294,967,295; generated by default | Reproduces the optimized source route when source order may move. |
| Use Last.fm guidance | Inherited; optional | Enables failure-tolerant track and artist evidence through LastMix. |
| Similar-track guidance | 0Ã¢â‚¬â€œ100%; default 75 | Bounded support from recording relationships for each possible insertion. |
| Similar-artist guidance | 0Ã¢â‚¬â€œ100%; default 75 | Bounded support from local artist relationships and the original-collection fallback. |
| Exact number of additions | 1Ã¢â‚¬â€œ100; default 1 | Required total, further limited by the current internal-gap capacity of S Ã¢Ë†â€™ 1. |
| Output | Create copy | Preview is read-only. Creating a verified copy works; source overwrite is planned. |

#### How the exact combination is found

Exact mode uses the same candidate inventory, Last.fm evidence strengths, bounded guidance adjustment, two-leg contextual scoring, repeat constraints, and fixed acoustic gates as automatic mode. It does not use the automatic trigger and does not simply take the first eligible gaps.

At each original gap the search branches into **skip this gap** and the best admissible insertion choices. After each insertion it re-evaluates the objective for the complete evolving route. States are grouped by their current number of additions, and only a bounded set of the best routes continues. The current native beam width is 64; the plugin supplies up to five retained candidate alternatives per gap.

At the end, the optimizer selects the best route containing exactly N additions. If no retained route reaches N, it returns no partial playlist and reports whether the requested count exceeded structural capacity or was not found within the bounded search.

The current plugin requests one bridge at most per internal original gap and disables opening and closing slots. With S source songs, the UI therefore allows no more than S Ã¢Ë†â€™ 1 additions. The native optimizer already contains bounded multi-track-gap and endpoint support, but those controls are not connected.

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

This is for a small playlist that says Ã¢â‚¬Å“more music like this.Ã¢â‚¬Â Every original song acts as part of one musical mood board. Better Call Bliss searches the analyzed songs in your local Lyrion library for tracks that fit that complete mood board, selects enough to reach the requested size, and finally arranges originals and additions together.

Newly selected songs do not change the mood board. If you start with soul and metal seeds, the first addition cannot pull the next search farther and farther toward an unrelated style. The original collection remains the reference throughout.

All original songs are retained, but their order may change. **Grow from these seeds** always optimizes the final order because arranging the enlarged collection is part of the workflow.

#### Options for Grow from these seeds

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Final playlist size | 3Ã¢â‚¬â€œ500; default 25 | Exact target size; it must be greater than the number of original seeds. |
| Musical context window | 1Ã¢â‚¬â€œ50; inherited from BlissMixer | Controls final route ordering only. Membership relevance always uses every original seed. |
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0Ã¢â‚¬â€œ10,000; inherited | Limits artist membership capacity and constrains the final route. Zero disables it. |
| Album look-back | 0Ã¢â‚¬â€œ10,000; inherited | Limits album membership capacity and constrains the final route. Zero disables it. |
| Additional route-search attempts | 0Ã¢â‚¬â€œ500; default 50 | Adds seeded starts when arranging the completed membership. |
| Variation | 0Ã¢â‚¬â€œ100%; default 25 | Controls membership-sampling breadth and enables per-job final-route diversity. |
| Generation seed | 0Ã¢â‚¬â€œ4,294,967,295; generated by default | Reproduces both membership sampling and final routing. |
| Use Last.fm guidance | Inherited; optional | Enables failure-tolerant recording and artist evidence from the complete original seed set. |
| Similar-track guidance | 0Ã¢â‚¬â€œ100%; default 75 | Bounded support for candidates related to any original recording. Zero ignores recording evidence. |
| Similar-artist guidance | 0Ã¢â‚¬â€œ100%; default 75 | Bounded support for candidates whose artist relates to the original artist set. Zero ignores artist evidence. |
| Output | Create copy | Preview is read-only. Creating a verified copy works; source overwrite is planned. |

#### How new playlist members are selected

Seed growth separates two questions:

- **Which songs belong in this playlist?** Every original source song is used together as one immutable relevance context. The context-window setting does not truncate this set.
- **In which order should they play?** After membership is fixed, the normal route optimizer uses rolling preceding contexts.

Every eligible local candidate is scored in parallel against the same complete-source relevance model. Added tracks never become relevance seeds.

With Variation and both Last.fm guidance values at zero, the quality pool contains only as many top acoustic candidates as are requested. Otherwise it may contain up to ten times the requested additions, capped by the pluginÃ¢â‚¬â„¢s current shortlist limit of 256 and by candidate availability.

With Variation above zero, candidates are reproducibly sampled without replacement. Better acoustic ranks receive exponentially higher weight; increasing Variation makes lower-ranked qualified candidates more likely. Separate recording and artist evidence strengths supply bounded multiplicative support according to their two job percentages.

At zero Variation, membership remains deterministic. Last.fm evidence may move a candidate upward by at most 20% of the Bliss-qualified pool, scaled by its evidence strength and the configured controls. It is not a quota and cannot pull a candidate into the pool from outside the Bliss relevance shortlist.

Membership selection also limits how many tracks from one artist or album may enter, based on the final target size and repeat windows. Tracks beyond the quality pool remain a deterministic feasibility fallback when better-ranked pool members cannot satisfy those capacities.

Once the exact target membership is complete, all originals and additions are passed to the standard route optimizer. Artist and album windows are then enforced on the final sequence.

~~~mermaid
flowchart TD
    A["All original tracks<br/>immutable relevance set"] --> B["One relevance model<br/>from the complete source set"]
    C["Every eligible local<br/>analyzed candidate"] --> D["Score against that same model"]
    B --> D
    D --> E["Acoustic rank and<br/>bounded quality pool"]
    L["Optional Last.fm<br/>track and artist evidence"] --> F
    E --> F["Reproducible membership selection<br/>using Variation and bounded guidance"]
    F --> G["Apply artist and album<br/>membership capacities"]
    G --> H{"Exact target reached?"}
    H -- No --> X["Fail without partial output"]
    H -- Yes --> I["Fix complete membership"]
    I --> J["Optimize order with rolling<br/>preceding contexts"]
    J --> K["Prove target, sources, locality,<br/>uniqueness and repeat windows"]
~~~

## Similarity supplied by BlissMixer

Similarity scoring is an input to the playlist workflows above, not Better Call BlissÃ¢â‚¬â„¢s main feature. The algorithms and learned-matrix capability come from the [BlissMixer implementation and its algorithm guide](https://github.com/chrober/lms-blissmixer/blob/main/ALGORITHMS.md). Better Call Bliss depends on a compatible lms-blissmixer installation and reuses the shared native Bliss scoring core so both applications interpret the 23 Bliss audio features consistently.

**Adaptive dynamic weighting** and **Static weighted distance** are connected in Better Call Bliss. Extended Isolation Forest remains a BlissMixer capability for now; its Better Call Bliss option is visible but disabled until native playlist-routing semantics are implemented.

### Adaptive dynamic weighting Ã¢â‚¬â€ working

Adaptive behaves like a DJ who listens for the common thread in the music immediately before the next song. If those songs share a rhythmic feel, rhythm becomes an important clue. If they instead share a similar tone or harmony, Adaptive follows that clue. The important qualities can change as the playlist develops.

**Musical context window** tells it how many previous songs to consider. A value of 3 means Ã¢â‚¬Å“judge the next song using up to the previous three songs.Ã¢â‚¬Â Near the beginning, it uses the smaller context available.

#### Options for Adaptive scoring

| Option | Range / default | Effect |
| --- | --- | --- |
| Musical context window | 1Ã¢â‚¬â€œ50; inherited from BlissMixer | Maximum preceding tracks used for each directional route or bridge score. Seed-growth membership deliberately uses all original seeds instead. |
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |

#### How Adaptive calculates distance

Each analyzed track has the same 23-feature Bliss vector: tempo, timbre, loudness, and chroma measurements.

For a non-empty context:

1. The optimizer calculates the arithmetic mean of the context vectors. This is the target sound.
2. With two or more context tracks, it derives a variance-based matrix. Features on which those tracks agree receive more influence; features on which they differ receive less.
3. It blends that matrix with the learned Mahalanobis matrix using **Learned-matrix blend**.
4. It calculates the Mahalanobis distance from the candidate vector to the context mean. Smaller means a closer fit.

With one context track, variance cannot be derived from the context. If a learned matrix is available, Better Call Bliss uses it for that one-track distance. If it is absent, the optimizer falls back to the same Static BlissMixer feature-weight matrix used by the explicit Static strategy.

Distance is directional because the context comes from the proposed route prefix. A Ã¢â€ â€™ B and B Ã¢â€ â€™ A need not receive the same score.

#### Is a learned matrix optional?

For BlissMixer and the shared Adaptive algorithm, **yes**. A learned matrix is optional personalization produced by the similarity survey and training process:

- with two or more context tracks and no learned matrix, Adaptive can use the variance-based matrix by itself;
- with two or more context tracks and a learned matrix, **Learned-matrix blend** combines the learned and variance-based matrices;
- with one context track, no variance matrix can be calculated; BlissMixer can fall back to its standard algorithm when the learned matrix is absent.

For Better Call Bliss, **yes** as well. The optimizer request may omit `artifacts.learned_matrix`. In that case:

- with two or more context tracks, Adaptive uses the variance matrix by itself;
- with one context track, Adaptive uses the Static BlissMixer feature-weight matrix as the fallback;
- the result artifact records the hash of whichever scoring matrix was actually used for one-track/static fallback or learned-matrix scoring.

This makes **Learned-matrix blend = 0** unsurprising: multi-track contexts use pure variance, and one-track contexts use either the learned matrix if supplied by an Adaptive job or the Static fallback when no learned matrix exists. Explicit Static mode always uses the fixed Static matrix.
~~~mermaid
flowchart TD
    A["Take the applicable context tracks"] --> B["Read their 23-feature vectors"]
    B --> C["Calculate context mean"]
    B --> D{"How many context tracks?"}
    D -- One --> E{"Learned matrix<br/>available?"}
    E -- Yes --> J["Use learned matrix"]
    E -- No --> K["Use Static BlissMixer<br/>feature weights"]
    D -- Two or more --> F["Calculate variance-based matrix"]
    F --> G["Blend learned matrix when supplied;<br/>otherwise use variance alone"]
    J --> H["Mahalanobis distance:<br/>candidate to context mean"]
    K --> H
    G --> H
    H --> I["Smaller contextual distance<br/>means a smoother fit"]
~~~

### Static weighted distance - working

Static mode lets BlissMixer users give permanent instructions such as "care a lot about rhythm, somewhat about tone, and less about harmony." The same priorities apply to every playlist decision.

Better Call Bliss reads BlissMixer's four static sliders - tempo, timbre, loudness, and chroma - and expands them to the 23 Bliss audio features in the same proportions used by BlissMixer. The native optimizer turns those feature weights into a fixed diagonal scoring matrix. Route search, bridge tests, repeat constraints, Variation, Last.fm guidance, and result proofs then run through the same playlist workflow as Adaptive.

#### Options for Static scoring

| Option | Range / default | Effect |
| --- | --- | --- |
| Mixing strategy | Static; inherited from BlissMixer when configured there | Uses the fixed BlissMixer metric priorities for every contextual distance. |
| Musical context window | 1-50; inherited from BlissMixer | Controls how many preceding tracks define the contextual mean. Static keeps the same feature weights no matter how many context tracks are available. |
| Static metric sliders | Current BlissMixer settings | Read from BlissMixer for the job. They are not edited in Better Call Bliss yet; choose Adaptive if you want only dynamic weighting. |

~~~mermaid
flowchart TD
    A["Read BlissMixer static sliders"] --> B["Expand tempo, timbre,<br/>loudness and chroma to<br/>23 Bliss feature weights"]
    B --> C["Build fixed diagonal<br/>scoring matrix"]
    D["Context tracks"] --> E["Calculate context mean"]
    C --> F["Score candidate to mean<br/>with fixed weights"]
    E --> F
    F --> G["Route, bridge or growth<br/>decision uses that distance"]
~~~


### Extended Isolation Forest Ã¢â‚¬â€ planned for Better Call Bliss

Forest mode uses several example songs to learn the broad sound they share, then favors songs that fit that group and treats outsiders as less suitable.

Bringing it into playlist routing still requires decisions about the minimum context near the start of a route, fallback behavior, when to rebuild a model after a route change, and how to score both sides of a bridge. Better Call Bliss therefore disables it instead of silently substituting another scorer.

## Behavior shared across workflows

The workflow tables omit **Track look-back** because every current workflow already requires unique playlist membership. Its compatibility value is retained in requests and result proofs, but changing it cannot alter the generated playlist today.

### Variation and reproducibility

Variation asks Better Call Bliss to explore different qualified answers. It does not change Bliss features, similarity matrices, repeat windows, or bridge acceptance gates.

For movable routes, a generated or supplied seed changes the greedy restart paths. The percentage currently acts as an on/off switch for route diversity: zero uses a fixed baseline seed; any positive value uses the jobÃ¢â‚¬â„¢s generation seed.

For seed growth, the percentage additionally controls membership sampling inside the quality pool. Higher values flatten the acoustic weighting and make lower-ranked qualified candidates more likely.

Automatic and exact bridge selection is otherwise deterministic after the base source route has been chosen. Preserve-order jobs may return the same result at different seeds because their anchors cannot move.

A recorded generation seed reproduces the same request and result across worker counts when the library, artifacts, and options are unchanged.

### Last.fm track and artist guidance

Last.fm is an optional guide for choosing new songs. It never replaces Bliss similarity and never causes a non-local or otherwise invalid track to be admitted.

Better Call Bliss uses the installed LastMix plugin without user credentials. It requests similar tracks once for every distinct original recording and similar artists once for every distinct original artist. Recording relationships are endpoint-local. Artist relationships are recorded both for endpoint-local use and for the complete original collection fallback.

The per-job **Similar-track guidance** and **Similar-artist guidance** controls range from 0 to 100 and both default to 75. They scale a bounded supporting signal after locality, repeat, and Bliss acoustic qualification. Even 100 cannot make a rejected acoustic candidate acceptable. Zero ignores that evidence type without disabling the other one.

Bridge modes use the signal to rank admissible two-leg insertions. Seed growth uses track and artist evidence from the complete immutable source set to support membership ranking inside its Bliss-qualified pool. Last.fm has no effect on fixed-membership Reorder only jobs.

Provider responses are frozen with their raw score or rank so the report can explain the support used by that run. Missing LastMix, no Internet access, malformed responses, and provider errors fall back to Bliss without failing the playlist job. Service-wide offline, unavailable, and rate-limit errors open a per-job circuit breaker so the remaining track and artist requests are not repeated.

### Safety and result proofs

Before you save anything, Better Call Bliss checks that the proposed playlist still contains what you asked for and that every addition is a real local Lyrion track.

A successful result proves the invariants relevant to its workflow:

- every original track is retained exactly once;
- preserved originals remain the same ordered subsequence;
- every addition belongs to the frozen current LMS-local inventory;
- membership is unique;
- requested exact or target counts are satisfied; and
- artist, album, and track-repeat rules hold.

Preview writes no playlist. Only the separate user-confirmed action invokes LyrionÃ¢â‚¬â„¢s playlist serializer and verifies the saved file and catalog order.
