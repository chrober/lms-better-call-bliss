# Playlist optimization modes and options

Better Call Bliss turns a saved playlist or player-queue snapshot into a smoother listening experience. You decide whether existing songs may move, whether new songs may be added, and how much freedom the optimizer has. Playlist and queue-editor jobs preview the result, and nothing is changed until you accept it. The three track-context **Bliss me there...** shortcuts are intentionally different: they run in the background and apply a successful route automatically.  

This document describes the current implementation. **Working** means the choice is available in the Lyrion job editor. **Planned** means it is shown but cannot yet be selected.

## Choose the result you want

| If you want to... | Choose... | What happens |
| --- | --- | --- |
| Smooth out a shuffled collection without adding songs | [Optimize source order](#reorder-existing-tracks-only) + Additional tracks: No additions | The same songs are rearranged; nothing is added or removed. |
| Keep a carefully chosen order but soften awkward changes | [Preserve source order](#preserve-source-order-and-fill-gaps) + Additional tracks: Improve difficult transitions | Original songs stay in their current order; helpful songs may be inserted between them. |
| Make an existing playlist exactly N songs longer | Optimize or [Preserve](#preserve-source-order-and-fill-gaps) + Additional tracks: [Extend playlist](#extend-playlist) | Treat the current playlist as the thing to extend. Better Call Bliss adds the requested number of suitable local songs and then orders or places them according to the chosen source-order policy. |
| Turn a tiny seed list into a full mix with the same general character | Additional tracks: [Extend playlist](#extend-playlist) + Chosen amount: Reach a final track count | Treat the input as examples of a desired sound. Better Call Bliss selects enough related local songs to reach the target size, then arranges originals and additions together. |
| Get a different but still sensible result | [Increase Variation](#variation-and-reproducibility) | Search explores different good alternatives without relaxing its quality and repeat rules. |
| Let related recordings and artists support addition choices | [Enable Last.fm guidance](#lastfm-track-and-artist-guidance) | Similar-track and similar-artist evidence help rank suitable additions; Bliss remains the acoustic quality check. |
| Replace the upcoming queue with a fluent path from the current song | [Bliss me there...](#bliss-me-there) from a track context menu | The current song keeps playing. Later queue entries are excluded from the route context and replaced by the intermediates and destination after a live-current-song check. |
| Visit a chosen song, then return to the existing queue | [Bliss me there... and back again!](#bliss-me-there) from the same track context menu | The current song is the start, the chosen song is a required waypoint, and the first upcoming song is the rejoin point. The complete excursion is inserted before the otherwise unchanged upcoming queue. |
| Append a fluent path from the queue end to a chosen song | [Bliss me there... when we're through!](#bliss-me-there) from the same track context menu | The queue end and chosen track stay fixed. Better Call Bliss builds the route in the background and appends its intermediates and destination when every check succeeds. |

Three job choices work together:

1. **Source-track order** decides whether songs already in the playlist may move.
2. **Additional tracks** asks for the listener-facing purpose: no additions, improve difficult transitions, or extend the source by a chosen amount. **Extend playlist** opens the second **Chosen amount** selector for exact additions, final track count, or double track count; **Reach a final track count** is also the replacement for the former separate target-size workflow.
3. **Mixing strategy** supplies the similarity measurement used by those playlist operations. Better Call Bliss reuses this capability from BlissMixer; it is not the main feature being selected here.
4. **Candidate library** limits every newly generated track to the selected Lyrion virtual library. Existing source, history, destination, waypoint, and queue-rejoin tracks remain valid anchors even when they are outside that view.

## Features at a glance

### Playlist operations

| Choice | Status | Best when... | What changes |
| --- | --- | --- | --- |
| [Optimize source order](#reorder-existing-tracks-only) | Working | The songs are right, but the order is not. | Existing songs may move; the membership stays the same unless an addition mode is also selected. |
| [Preserve source order and fill gaps](#preserve-source-order-and-fill-gaps) | Working | The current order matters: chronology, story, album-like flow, or deliberate DJ arc. | Existing songs stay in their current order; additions can be placed around those anchors. |
| [No additions / reorder existing tracks only](#reorder-existing-tracks-only) | Working | You want a cleaner sequence without changing the track list. | No new tracks are added; no source tracks are removed. |
| [Improve difficult transitions](#add-automatically) | Working | The playlist mostly works, but a few handovers are awkward. | Adds zero or more bridge tracks only where the frozen source route has difficult transitions. |
| [Extend playlist](#extend-playlist) | Working | The playlist is already the thing you want, just too short. | Adds a chosen amount of local songs. Addition similarity is based on the complete original source set, not on one gap at a time; originals remain required members. |
| [Bliss me there...](#bliss-me-there) | Working | You want to arrive at one selected local track after the queue, directly after the current song, or as an excursion before the existing upcoming queue. | The three sibling actions append, replace upcoming tracks, or insert a route through the destination and back to the first upcoming track. All use locked anchors and validate them before changing the queue. |
| Add N bridge tracks per source transition | Planned | You want a strict "put the same number of bridges inside every existing gap" placement rule. | Future preset; different from Extend playlist because the number of additions is tied to each source transition. |
| Duration target | Planned | You want "make this about 90 minutes" rather than "make this 30 tracks." | Future target unit; track-count targets already work through Extend playlist. |

### Similarity and evidence inputs

| Choice | Status | Role |
| --- | --- | --- |
| [Adaptive dynamic weighting](#adaptive-dynamic-weighting--working) | Working | BlissMixer's adaptive similarity measurement for each decision. |
| [Static weighted distance](#static-weighted-distance--working) | Working | BlissMixer's fixed user priorities. |
| [Extended Isolation Forest](#extended-isolation-forest--planned-for-better-call-bliss) | Planned | BlissMixer's model of the sound shared by several example songs. |
| [Last.fm track and artist guidance](#lastfm-track-and-artist-guidance) | Working, optional | Extra evidence for ranking suitable additions; Bliss remains the acoustic gate. |
| [Candidate library](#candidate-library-for-all-addition-modes) | Working | Restricts generated tracks to the active or explicitly selected Lyrion virtual-library membership. |

## How the pieces fit together

The Better Call Bliss plugin resolves Lyrion tracks, reads per-job options, freezes the LMS-local candidate inventory, and optionally asks LastMix for Last.fm track and artist relationships. The native [bliss-playlist-optimizer](https://github.com/chrober/bliss-playlist-optimizer) performs scoring and bounded search. Only the plugin writes playlists or player queues. Editor jobs require explicit acceptance; the **Bliss me there...** shortcuts automatically append, replace upcoming tracks, or insert an excursion only after the background route and matching live-anchor checks succeed.  

## Candidate discovery: which tracks influence the choice?

"Candidate discovery" does not mean the same thing in every workflow. Better Call Bliss first decides **which tracks are allowed to be considered**, then each workflow decides **which source tracks the candidates should resemble**, and only afterwards decides **where selected tracks belong**. Keeping those steps separate makes the strategies much easier to understand.

| Workflow | Tracks that may be chosen | Tracks used to discover or score them | Do selected additions become new discovery seeds? |
| --- | --- | --- | --- |
| [Reorder only](#reorder-existing-tracks-only) | Only source tracks not yet placed in the proposed route | Up to N already placed source tracks immediately before the next position | There are no additions. Each placed source track becomes part of the context for the next position. |
| [Improve difficult transitions](#add-automatically) | Eligible local analyzed library tracks | The local gap `A -> B`, including up to N preceding route tracks ending in A; the complete original source set supplies the frozen percentile scale and Last.fm artist fallback, not the primary acoustic target | The per-job Adaptive gap-context choice decides whether inserted tracks may recalculate feature weights inside a gap. A selected bridge still affects the context used for later gaps, but it does not turn the workflow into whole-playlist growth. |
| [Extend playlist](#extend-playlist) | Eligible local analyzed library tracks | Every original source track together as one fixed musical reference | No. All additions are selected against the unchanged original source set. They influence only the later placement or route search. |
| [Bliss me there...](#bliss-me-there) | Eligible local analyzed library tracks | For a one-way route, the chosen start and destination drive one acoustic shortlist. For **and back again**, the current song, selected waypoint, and first upcoming rejoin define two gap-specific shortlists: start-to-waypoint and waypoint-to-rejoin. For Adaptive, a bounded analyzed queue prefix ending at the start constructs the frozen per-run matrix; this context and all locked anchors can also provide Last.fm and repeat evidence. | No. Intermediates are chosen from the frozen shortlist for their leg. An outward path is carried into return-leg evaluation, so uniqueness and repeat windows apply across the complete excursion, but chosen tracks do not recruit new candidates. |

Here, N means **Musical context window**. "Eligible local analyzed library tracks" means the intersection of usable `bliss.db` rows, current local LMS tracks, and the frozen **Candidate library** membership after source-track exclusions and the captured BlissMixer genre policy. Last.fm can support tracks already in that pool; it cannot add remote tracks or bypass Bliss, LMS membership, the virtual-library boundary, or genre checks.  

The diagrams below use four recurring stages:

1. **Allowed pool:** which real local tracks may be considered at all.
2. **Discovery reference:** which source tracks define what "suitable" means for this workflow.
3. **Qualification and ranking:** Bliss distance, repeat rules, optional Last.fm support, and Variation.
4. **Placement:** where the chosen membership is put in the result.

The diagrams are orientation maps, not complete algorithm specifications. They show which tracks influence a choice and what may be produced; the prose below each diagram describes the exact gates, bounds, and fallback behavior.

Inside a diagram, `A -> B -> C` is a playlist or queue in playback order. `+X` marks a track added by Better Call Bliss.

## Understanding transition-quality percentiles

Better Call Bliss uses the shared **Transition-quality threshold percentile** in two automatic workflows: **Improve difficult transitions** uses it to decide which existing playlist gaps deserve examination, while **Bliss me there... / Choose automatically** uses it as the neighboring-leg quality target for a destination route. The setting does not control **Reorder only**, **Extend playlist**, or the number of intermediates in an exact-count destination route.  

The percentage is a **rank of acoustic distance**, not “percent similar.” A result at the 30th percentile means that roughly 30% of the relevant comparison distances are smaller - acoustically closer - while roughly 70% are equal or larger. Lower values therefore mean a closer, stricter transition. Lowering the configured threshold moves the decision boundary left: more transitions are searched, and an automatically accepted result must clear a stricter boundary.  

| Workflow | Reference population | How the threshold is used |
| --- | --- | --- |
| [Improve difficult transitions](#add-automatically) | One frozen distribution of contextual distances built from the original source playlist | An original gap above the threshold is examined for a useful bridge. A gap at or below it remains unchanged. |
| [Bliss me there... / Choose automatically](#bliss-me-there) | For each route leg `A -> B`, the fixed-matrix distance from A to every eligible local analyzed library track | A direct transition or complete path meets the target only when its worst neighboring leg is at or below the threshold. Cautious mode may still search below it when acoustic models strongly disagree. |

~~~mermaid
flowchart LR
    P0["0th<br/>closest"] --> P30["30th<br/>strict"] --> P50["50th"] --> P70["70th<br/>configured boundary"] --> P90["90th"] --> P100["100th<br/>furthest"]
    P70 -. "lower the setting: boundary moves left; more searches" .-> P30
    A["At or below the boundary<br/>automatic workflow may accept or leave unchanged"] --- P50
    S["Above the boundary<br/>automatic workflow searches for an improvement"] --- P90
    classDef accepted fill:#d9ead3,stroke:#38761d,color:#000;
    classDef searched fill:#fce5cd,stroke:#b45f06,color:#000;
    class P0,P30,P50,P70,A accepted;
    class P90,P100,S searched;
~~~

The percentile number is shared, but its comparison population is deliberately workflow-specific. It therefore expresses the same **lower-is-stricter rank concept**, not an identical global acoustic cutoff across every job.  

## Bliss me there

Use any of the three commands from a local track's context menu when a player already has something in its queue and you want to arrive at the selected song smoothly. Each command closes the context menu and starts a background job with the saved **Bliss me there...** defaults. None opens the Extras page or requires a separate Accept button. The job remains visible under **Running and recent previews** for status or error review.  

- **Bliss me there...** fixes the current song as the route start. It captures context only up to that queue position, keeps the current song and playback state, removes the later queue entries only after successful validation, and appends the intermediates plus destination in their place.  
- **Bliss me there... and back again!** fixes the current song as the start, the selected song as a mandatory waypoint, and the first upcoming song as the rejoin. It inserts the outward route, waypoint, and return route immediately after the current song without removing the captured upcoming queue.  
- **Bliss me there... when we're through!** fixes the current queue end as the route start. It keeps every existing queue entry and appends the intermediates plus destination after validating that the queue end is unchanged.  

The selected song is the fixed destination for the two one-way commands and a fixed waypoint for **and back again**. The latter also locks the first upcoming song as its rejoin anchor. A bounded local queue prefix ending at the chosen start is captured separately as immutable context: it can provide Adaptive acoustic context, repeat context, and optional Last.fm evidence, but its earlier tracks are not route members, acoustic path endpoints, or output tracks. For the queue-end command this prefix may include songs that are still upcoming. For both current-song commands, later queue entries are excluded from backward-looking context. Repeats already present in captured history are tolerated.  

**Choose automatically** first measures the unbridged locked-anchor edges under the configured BlissMixer strategy: start-to-destination for a one-way route, or start-to-waypoint and waypoint-to-rejoin for an excursion. Static uses the current Static feature weights. Adaptive builds one contextual matrix from the bounded captured context plus the route start, applies the configured learned-matrix blend, and uses the same learned/Static fallback rules as BlissMixer. **Normal** caution may use the unbridged route when the minimum is zero and its governing view meets the target. **Cautious** additionally compares available Static and learned-only measurements and starts a bridge search when a secondary view disagrees with the governing view by at least 25 percentile points. It then uses the worst available whole-path verdict for acceptance and ranking, so a route cannot win merely because one model overlooks an abrupt change. A dedicated layered search covers every permitted total count from **Minimum intermediate tracks** through **Maximum intermediate tracks**. For an excursion, that is one budget shared by the outward and return legs rather than a separate count per leg. Automatic chooses the shortest complete route that meets the adjacent target across the applicable model view or views. If no path reaches the target and zero intermediates are permitted, every best-effort bridge path is compared with the unbridged locked-anchor route: Better Call Bliss inserts bridges only when they improve the cautious worst-model result by at least one percentile point. Otherwise it keeps the unbridged route and explicitly reports that no beneficial bridge was found. A positive minimum remains an explicit request for intermediates. **Use an exact count** runs the same adjacent path search for precisely the requested total number of intermediates and remains all-or-nothing.  

Candidate discovery is frozen before the layered path search begins. For a one-way route, the acoustic prefilter compares every eligible candidate C with both endpoints: `start -> C` and `C -> destination`. For **and back again**, it creates that same kind of balanced shortlist independently for `start -> waypoint` and `waypoint -> rejoin`. Optional Last.fm matches from each leg's anchors and a bounded suffix of captured context reserve some places in the relevant shortlist. The optimizer searches complete outward paths, then evaluates each retained outward result together with return paths under the remaining shared budget. This makes route membership and repeat-window checks span both legs. A chosen intermediate affects the next path edge and repeat checks, but it does not expand either pool or trigger another library-wide discovery round.  

For every final adjacent `A -> B` edge, the optimizer ranks its fixed-matrix distance against `A -> every current LMS-local analyzed track` under the same matrix. That whole local reference population turns the raw edge distance into the destination-routing percentile described under [Understanding transition-quality percentiles](#understanding-transition-quality-percentiles); it is not another candidate pool. The result identifies the governing Adaptive-context or Static role and hash, records the effective Adaptive algorithm, seed identities, configured learned share, fallback reason, available direct-edge model verdicts, and every final edge, route sum, raw bottleneck, and worst adjacent percentile. Under Cautious it reports and applies distinct Static and learned-only whole-route measurements as well. Earlier listening-history edges are not included in this destination-path quality result.  

The destination is explicit user intent, so a conflict already present solely between immutable listening history and that destination does not reject the job. Existing history may contain repeated tracks, artists, or albums. Every newly generated intermediate remains unique and is checked against the destination, route members, and history inside the configured artist, album, and track windows. Last.fm similar-track and similar-artist evidence supports candidate ranking, but Bliss remains the primary path-quality evidence. Variation is applied only among complete routes inside a narrow quality band, so it can change a reproducible choice without relaxing repeat rules or turning a clearly worse route into a candidate.  

#### Candidate discovery for Bliss me there

"Eligible" does not yet mean "similar." Better Call Bliss first intersects local audio tracks in the current LMS catalog with non-ignored `TracksV2` rows having the same exact Bliss file identity. From that intersection, the optimizer removes the chosen route start, destination or waypoint, optional rejoin, and tracks with the same normalized artist-and-title identity as any of those anchors. The result is the eligible pool described more generally under [Candidate library for all addition modes](#candidate-library-for-all-addition-modes).  

Earlier listening history is not removed wholesale at this stage because it is context, not route membership. The configured repeat windows later prevent a newly chosen intermediate from repeating a recent track, artist, or album where applicable. Last.fm evidence can support the ranking of an eligible local track but cannot make an ineligible, remote, unanalyzed, ignored, or stale Bliss row usable.

~~~mermaid
flowchart LR
    L["Local LMS audio tracks<br/>A, B, U, X, Y, Z, ..."] --> I["Keep exact usable<br/>matches in bliss.db"]
    I --> E["Eligible pool after removing<br/>locked route anchors"]
    Q["Chosen queue prefix<br/>... -> H -> A (start)"] --> F["Find A -> B"]
    D["Selected song<br/>B"] --> F
    E --> F
    M["Optional Last.fm<br/>ranking support only"] -.-> F
    F --> R["One-way result<br/>... -> H -> A -> +X -> B"]
    U["For and back again:<br/>first upcoming track U"] --> G["Also find B -> U<br/>within the shared budget"]
    F --> G
    E --> G
    G --> T["Inserted excursion<br/>A -> +X -> B -> +Y -> U -> ..."]
~~~

#### How Bliss similarity becomes a path

The current implementation does **not** interpolate a straight line from A's feature vector to B's feature vector and then look for songs near evenly spaced points. It performs a bounded graph search through real tracks that are actually available in the frozen shortlist.

Every track has a 23-value Bliss feature vector. A fixed matrix `M` turns the difference between two vectors into an adjacent-track distance, conceptually `sqrt((x - y)^T M (x - y))`. A smaller distance means the two recordings are more similar under that view of tempo, timbre, loudness, chroma, and the other Bliss dimensions.

**Bliss me there... does not learn or fit a matrix from A and B.** In particular, the destination B never teaches the optimizer what should count as similar. The configured strategy determines the governing view:

- **Static view:** the optimizer mechanically constructs a diagonal 23-by-23 matrix from the Static feature weights captured from BlissMixer. It may reconstruct this matrix when the job starts, but it does not derive it from the source or destination.
- **Adaptive-context view:** the optimizer takes the last analyzed tracks from immutable history and then A, capped by BlissMixer's **Musical context window**. With two or more seeds it derives the same variance matrix as BlissMixer and blends the optional learned matrix by **Learned-matrix blend**. With one seed it uses the learned matrix when available. With too little context and no learned matrix, or when variance cannot be calculated and no learned fallback exists, it uses the current Static matrix.
- **Learned-only view:** when a learned artifact exists, Cautious mode can measure it separately as diagnostic and safety evidence. It was produced earlier by the learning workflow; this run never retrains or modifies it.

This is the same Adaptive selection and fallback contract used by BlissMixer:

1. One seed plus a learned matrix uses the learned matrix.
2. Two or more seeds without a learned matrix use seed variance.
3. Two or more seeds with a learned matrix blend learned and variance matrices at the configured percentage.
4. A failed variance calculation falls back to learned when available, otherwise to Static.
5. One seed without a learned matrix falls back to Static.

The resulting per-run Adaptive matrix is then **frozen** while candidate paths are explored. Newly considered intermediates do not become new matrix seeds, and the optimizer does not create imaginary target points between A and B. Freezing makes the costs of `A -> X`, `X -> Y`, and `Y -> B` directly comparable and keeps large-library route search bounded. The result records its role, hash, effective algorithm, seeds, blend, and fallback details so the decision remains auditable.

The acoustic prefilter reduces a large library without assuming that one song must resemble both endpoints perfectly. For each locked gap, it reserves candidates closest to that gap's left anchor, candidates closest to its right anchor, and candidates with the best balanced pair of distances. A one-way route has the single gap `A -> B`. **And back again** has `A -> B` and `B -> U`, so it prepares two shortlists under the same frozen matrix. Optional Last.fm-supported tracks can reserve some additional shortlist positions, but their Bliss edge distances still govern the path.

The route itself is built one position at a time, but it is **not greedy**:

1. At the first layer, the optimizer considers partial paths such as `A -> X`, `A -> Y`, and `A -> Z`.
2. At the next layer, every retained partial path is extended with unused shortlisted tracks, producing alternatives such as `A -> X -> Y` and `A -> Z -> X`.
3. Repeat-window violations and paths that cannot approach B competitively are discarded. Search effort controls how many next choices per partial path and how many partial paths survive each layer.
4. When the requested layer is complete, B is appended and the real adjacent edges of every retained complete path are measured.

Complete paths are ordered primarily by their **worst adjacent jump**, then by their total adjacent distance. Last.fm support and deterministic identity ordering resolve later comparisons. Variation may choose reproducibly among complete routes in a narrow band around the acoustic winner; it does not make a poor edge acceptable.

For **and back again**, the outward candidates are not finalized independently and pasted onto an unrelated return route. The optimizer retains bounded outward alternatives for each possible outward bridge count, carries each complete outward route—including its chosen tracks and repeat state—into the return-leg search, and gives the return leg only the unused portion of the total budget. It then ranks the complete `A -> ... -> B -> ... -> U` alternatives by the worst adjacent jump across both legs and by their total distance. This is a bounded joint search, so search effort still controls breadth, but route uniqueness, repeat windows, quality reporting, and the bridge budget cover the excursion as one result.

~~~mermaid
flowchart LR
    S["Frozen shortlist<br/>X, Y, Z, ..."] --> G["Grow several partial paths<br/>A -> X; A -> Y; A -> Z"]
    G --> P1["A -> X -> B"]
    G --> P2["A -> Y -> Z -> B"]
    G --> P3["A -> X -> Z -> B"]
    P1 --> C["Prefer the smallest worst jump,<br/>then the smallest total distance"]
    P2 --> C
    P3 --> C
    C --> R["Chosen path<br/>A -> +Y -> +Z -> B"]
~~~

#### Options for Bliss me there

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Intermediate tracks | Automatic or Exact; saved plugin default | Automatic chooses the shortest complete path that meets the adjacent target. If none does and zero is permitted, a best-effort bridge must improve the cautious direct result by at least one percentile point; otherwise the direct destination is retained. Exact requires precisely the requested count. Both use the same dedicated adjacent path search. |
| Automatic bridge caution | Normal or Cautious; default Cautious | Used only by Automatic. Normal trusts the configured governing strategy. Cautious also searches on strong disagreement with available Static or learned-only views and requires candidate paths to hold up under every distinct available view. |
| Search effort | Fast; Balanced; Thorough; default Fast | Controls how many local candidates and partial paths are explored. Fast deliberately bounds the search; Balanced and Thorough trade more time and memory for a wider search. It never relaxes the quality target or repeat rules. |
| Minimum intermediate tracks | 0-8; default 0 | Lower bound used only by Automatic. Zero allows an unbridged locked-anchor route; a positive value forces Automatic to insert at least that many tracks. It must not exceed the maximum. For **and back again**, it is a total across both legs. |
| Maximum intermediate tracks | 0-8; default 4 | Upper bound used only by Automatic. It is also the budget for the best-effort comparison. Zero means no bridge tracks. For **and back again**, the two legs share this one total budget. |
| Exact intermediate tracks | 0-8; default 2 | Count used only by Exact. Zero explicitly requests no bridge tracks. For **and back again**, this exact total is distributed between the outward and return legs by the route search. |
| [Transition-quality threshold percentile](#understanding-transition-quality-percentiles) | 0-100%; plugin default 70 | Used only by Automatic. It is a library-relative distance rank, not percentage similarity. Lower is stricter and makes more direct transitions trigger a search. Cautious may search below the threshold when models disagree. |
| Musical context window | 1-50; inherited from BlissMixer | Caps the analyzed queue prefix ending at the chosen route start that is used to construct the per-run Adaptive matrix. It also bounds recent context that can contribute Last.fm evidence. Longer repeat windows can require more immutable history. |
| Mixing strategy | Inherited from BlissMixer | Static uses the current feature weights. Adaptive constructs a variance/learned blend from recent analyzed context and follows BlissMixer's learned/Static fallback rules. The chosen matrix stays fixed during this route search. |
| Learned-matrix blend | 0-100%; inherited from BlissMixerExt when available | Learned share of the Adaptive matrix when at least two seed tracks allow a variance matrix. Zero means pure variance; 100 means pure learned. The learned matrix is optional. |
| Artist, album, and track look-back | Inherited from BlissMixer | Hard constraints for generated intermediates; zero disables a window. The chosen destination itself remains fixed user intent. |
| Variation and generation seed | 0-100%; default 25 | Chooses reproducibly among complete routes close to the best adjacent bottleneck and route sum. Zero keeps the strict deterministic winner. |
| Last.fm track/artist guidance | Optional; track value inherited from BlissMixerExt, artist default 25% | Provides bounded supporting evidence for candidates related to the route start, destination, or captured context. Both remain overridable per job. If BlissMixerExt 0.3.0 or newer is unavailable, track guidance starts at a 25% fallback. Provider failure falls back to Bliss. |
| Output | Locked by the chosen context command | **Bliss me there...** validates the live current song, preserves it and playback, and replaces only the later queue entries with the route suffix. **Bliss me there... and back again!** validates both the current song and first upcoming track, then inserts only its route body before that unchanged upcoming track. **Bliss me there... when we're through!** validates the live queue end and appends the route suffix. |


#### How the bridge count and final route are chosen

~~~mermaid
flowchart TD
    S["Candidate shortlist"] --> M{"Bridge-count rule"}
    M -- Automatic --> A["Find the shortest<br/>acceptable route"]
    M -- Exact --> E["Find a route with exactly<br/>the requested bridge count"]
    A --> V["Validate route and<br/>chosen live source"]
    E --> V
    V -- Queue end valid --> O["Append route suffix<br/>... -> A -> +X -> B"]
    V -- Current song valid --> N["Keep A; replace upcoming queue<br/>... -> A -> +X -> B"]
    V -- Current and rejoin valid --> R["Insert excursion before U<br/>... -> A -> +X -> B -> +Y -> U -> ..."]
    V -- Invalid --> F["Change nothing"]
~~~

Before applying a result, Better Call Bliss compares the chosen live source with the captured route start. For the queue-end command, normal playback advancing through existing entries does not invalidate the job as long as the queue end is unchanged. For either current-song command, the current song must still be the captured start; otherwise the player may have advanced while the route was being built. **And back again** also requires the first upcoming song to remain its captured rejoin. A stale result is refused before any queue command is sent. The queue-end command never removes existing entries. The now-playing command deliberately removes only entries after the still-current song, then appends the generated intermediates and destination. The round-trip command removes nothing and inserts its route body immediately before the rejoin.

For **and back again**, the selected waypoint may also occur farther ahead in the preserved queue. The excursion still inserts a new visit to that waypoint and leaves the later occurrence untouched, because preserving the existing upcoming queue is the defining behavior of this command. Selecting the first upcoming song itself is rejected: that song is already the locked rejoin point, so it cannot simultaneously describe a meaningful excursion away from and back to the queue.

## Overall workflow

~~~mermaid
flowchart LR
    P["Source playlist or queue<br/>A -> B -> C"] --> J["Optimization job"]
    C["Eligible library tracks<br/>X, Y, Z, ..."] -.-> J
    O["Selected options"] --> J
    J --> V["Read-only preview<br/>A -> +X -> B -> C"]
    V -->|"user accepts"| W["Saved playlist or player queue"]
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
| Musical context window | 1-50; inherited from BlissMixer | Maximum number of immediately preceding route tracks used to judge each possible next song. |
| Learned-matrix blend | 0-100%; inherited from BlissMixerExt when available | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0-10,000; inherited | Forbids the same artist within that many preceding positions. Zero disables it. |
| Album look-back | 0-10,000; inherited | Forbids the same album within that many preceding positions. Zero disables it. |
| Additional route-search attempts | 0-500; default 50 | Adds seeded greedy starting routes. Zero still evaluates the built-in starts. |
| Variation | 0-100%; default 25 | Zero uses a fixed baseline route seed; any positive value uses the job's generation seed. |
| Generation seed | 0-4,294,967,295; generated by default | When Variation is positive, reusing the reported seed reproduces the same search. |
| Output | Choose after preview | Preview is read-only. Accepting the preview can create a verified copy, overwrite the source with confirmation, or send the result to a player queue. |

#### How the order is chosen

The candidate pool is exactly the source membership. For every proposed position after the first, the optimizer takes every source song not yet used in that attempted route and compares it with up to **Musical context window** immediately preceding songs. At the start only one preceding song may exist; farther into the playlist the full window is available. The first song has no incoming transition and therefore no similarity score. The rest of the LMS library and Last.fm are not candidate inputs in this workflow.

~~~mermaid
flowchart LR
    S["Source playlist<br/>A -> B -> C -> D"] --> O["Reorder source tracks only"]
    O --> R["Result playlist<br/>C -> A -> D -> B"]
~~~

The search evaluates:

- the original order;
- the reverse order;
- for the energy-aware search, an intensity-sorted start; and
- the configured number of seeded greedy restarts.

A greedy restart chooses a seeded first song. At each following position it scores unused songs against the current preceding context, strongly preferring the best of the top four. Each completed start is repeatedly improved by reversing a section or relocating one song. The changed route is then scored again because moving one song can alter several later context windows.

Artist and album look-back windows are hard constraints. A final route that violates either is rejected. Track repetition cannot occur because every fixed member is used exactly once.

The primary objective is:

    sum of all transition distances + 2 x the worst transition

The extra penalty makes one severe jump more important than its contribution to the sum alone.

In parallel, an energy-aware search favors a broad rise from approximately 0.25 intensity to 0.85 near 70% of the playlist, then a fall toward approximately 0.35. Intensity is a rank-based composite of five Bliss features. This route replaces the best purely transition-oriented route only if:

- its primary objective is no more than 8% worse; and
- its energy-arc error is at least 10% better.


### Preserve source order and fill gaps

Your original songs become fixed stepping stones. Better Call Bliss may place new stones between them, but it cannot swap or move the originals.

For example, A -> B -> C can become A -> X -> B -> Y -> C, but never B -> A -> C. This is useful for chronological playlists, albums, stories, or any sequence whose order already matters to you.

#### Options for Preserve source order

Preserve is an ordering policy used with **Improve difficult transitions** or **Extend playlist**. The chosen addition workflow supplies its remaining controls.

Preserve does not define a candidate-discovery method by itself. It fixes the source route that another addition strategy sees. **Improve difficult transitions** therefore discovers candidates separately for the fixed gaps `A -> B`, `B -> C`, and so on. **Extend playlist** still discovers its complete added membership against all original source tracks together, then places only that already selected membership around the anchors.

~~~mermaid
flowchart LR
    S["Source playlist<br/>A -> B -> C"] --> P["Preserve A, B and C<br/>as ordered anchors"]
    G["Improve:<br/>examine local gaps"] --> P
    E["Extend:<br/>use all originals together"] --> P
    P --> R["Possible result<br/>A -> +X -> B -> +Y -> C"]
~~~

| Option | Range / default | Effect with preserved anchors |
| --- | --- | --- |
| Source-track order | Preserve | Keeps every original track as an immutable ordered anchor. |
| Musical context window | 1-50; inherited from BlissMixer | Controls local bridge scoring and final placement. Extend membership discovery still uses every original source track together. |
| Learned-matrix blend | 0-100%; inherited from BlissMixerExt when available | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0-10,000; inherited | Applied to the source-anchor pre-check and final route. Zero disables it. |
| Album look-back | 0-10,000; inherited | Applied to the source-anchor pre-check and final route. Zero disables it. |
| Use Last.fm guidance | Inherited; optional | Asks LastMix for track and artist relationships. Failures transparently use Bliss alone. |
| Similar-track guidance | 0-100%; inherited from BlissMixerExt | Uses neighboring source recordings for difficult gaps, or the complete original source set for Extend membership. Better Call Bliss reads the current BlissMixerExt value when a job editor opens and uses 25 when that capability is unavailable. The value remains overridable for this job; zero ignores recording evidence. |
| Similar-artist guidance | 0-100%; default 25 | Uses endpoint-local artists with collection fallback for difficult gaps, or the complete original source set for Extend membership. Zero ignores it. |
| Output | Choose after preview | Preview is read-only. Accepting the preview can create a verified copy, overwrite the source with confirmation, or send the result to a player queue. |

#### How the anchors are protected

The input sequence is used directly as the source route. It is scored but not searched. The final result must prove that filtering out every added song yields the exact original sequence.

The source anchors must already satisfy the requested repeat windows. The current pre-check rejects an existing anchor conflict before trying insertions, even though a future implementation could attempt to separate those anchors with added tracks. Today such a job fails with a preserved-anchor conflict.

Additional route-search attempts have no effect because the anchors cannot move. Preserve plus **Reorder only** is rejected because it would leave the playlist unchanged.

### Candidate library for all addition modes

When Better Call Bliss adds music, it chooses only analyzed songs that Lyrion currently knows as local tracks and that belong to the per-job **Candidate library**. The Extras editor initially follows Material Skin's active virtual library when available, then the library assigned to the active player, with **All tracks** as the fallback. Users can override that choice before starting a preview. A stale Bliss database row, or a local song outside the selected virtual library, cannot become an addition merely because its acoustic data exists. This stage defines the allowed universe; it does not yet decide whether a track resembles a local gap, a complete source set, or a destination path.

#### How eligible candidates are frozen

Before search, the plugin freezes the selected Lyrion `library_track` membership and intersects it with usable rows in `bliss.db` and the current local LMS catalog. The membership checksum participates in the inventory cache key, so a rebuilt virtual library cannot silently reuse an obsolete allowlist. From that intersection it excludes:

- every source file already in the playlist; and
- another file with the same normalized artist-and-title identity as a source.

It then applies the current BlissMixer genre settings to every possible **new** track. Genre-group restriction, group glob patterns, **Match all genres**, and **Use track genre** follow BlissMixer's behavior. Source tracks—and immutable recent listening history for a destination shortcut—identify the acceptable groups. When no reference track belongs to a configured group, candidates belonging to configured groups are excluded while BlissMixer's implicit “other genres” remain together. An untagged candidate remains eligible.  

BlissMixer's **Filter Christmas music** switch is a separate hard candidate filter outside December, even when general genre restriction is disabled. During December the configured switch is deliberately inactive, matching BlissMixer. Existing source tracks, listening history, mandatory destinations, waypoints, and queue-rejoin anchors are never removed: both the Candidate library and genre settings constrain music chosen by Better Call Bliss, not the user's input.  

The remaining tracks form a checksum-protected candidate inventory for this job. Uniqueness and repeat rules are checked again during search, when the native result is resolved back to LMS tracks, and before persistence. The completed preview and information log report separate counts for candidates rejected by genre groups and by the Christmas filter.  

~~~mermaid
flowchart LR
    L["Local LMS library<br/>A, B, C, X, Y"] --> V["Keep selected Candidate library<br/>A, B, X"]
    V --> I["Keep tracks with<br/>matching Bliss rows"]
    B["bliss.db<br/>A, B, X, Y, Z"] --> I
    I --> G["Apply captured BlissMixer<br/>genre and Christmas policy"]
    G --> P["After removing source A, B<br/>eligible additions: X, Y"]
    F["Optional Last.fm<br/>ranking support only"] -.-> P
~~~

### Add automatically

In the current Extras UI this appears as **Improve difficult transitions when useful**.

Better Call Bliss first decides the order of the original songs - or respects your order if you chose Preserve. It then listens to each handover and asks: "Is this one of the awkward changes, and can one extra song genuinely improve it?"

The similarity base is local to the transition being repaired. Suppose the playlist contains A followed by B. A candidate C is used only if A -> C and C -> B both work, using the configured preceding context around that gap. It is not enough for C to resemble only A, only B, or the playlist in general. Last.fm guidance follows the same shape: similar-track evidence from A and B is strongest, endpoint artist evidence comes next, and the complete source artist pool is only a fallback when the local gap has no usable evidence.

If the original transition is already fine, or no candidate improves it safely, nothing is inserted. Therefore **Add automatically** can correctly add zero songs. This mode improves difficult transitions; it is not yet the repeat-window spacer-repair mode that can insert several tracks solely to separate repeated artists or albums.

#### Options for Add automatically

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Source-track order | Optimize by default | Either optimizes the originals before gap repair or preserves them as anchors. |
| Musical context window | 1-50; inherited from BlissMixer | Controls the preceding context for direct gaps and both candidate legs. |
| Learned-matrix blend | 0-100%; inherited from BlissMixerExt when available | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Adaptive gap context | Follow the evolving route (default), or Freeze weights per source gap | Adaptive only. Rolling recalculates feature weights after an inserted track enters the context. Frozen derives one matrix from the preceding route ending at the original left anchor and reuses it for every leg inside that source gap. |
| Artist look-back | 0-10,000; inherited | Rejects tentative and final routes with artists too close together. Zero disables it. |
| Album look-back | 0-10,000; inherited | Rejects tentative and final routes with albums too close together. Zero disables it. |
| Additional route-search attempts | 0-500; default 50 | Applies only when source order is Optimize. |
| Variation | 0-100%; default 25 | Can vary the optimized source route; it has no separate random bridge-selection step. |
| Generation seed | 0-4,294,967,295; generated by default | Reproduces the optimized source route when source order may move. |
| Use Last.fm guidance | Inherited; optional | Enables failure-tolerant track and artist evidence through LastMix. |
| Similar-track guidance | 0-100%; inherited from BlissMixerExt | Bounded support from tracks related to A, B, or both. Better Call Bliss reads the current BlissMixerExt value and falls back to 25 when needed; zero ignores recording evidence. |
| Similar-artist guidance | 0-100%; default 25 | Bounded support from related endpoint artists or, when no local evidence exists, the original artist collection. Zero ignores artist evidence. |
| Maximum additional tracks | 0-100; default 8 | Stops insertion after this many bridges. |
| [Bridge trigger percentile](#understanding-transition-quality-percentiles) | 0-100%; default 70 | Considers only original gaps above this point on the frozen source-playlist reference scale. |
| Output | Choose after preview | Preview is read-only. Accepting the preview can create a verified copy, overwrite the source with confirmation, or send the result to a player queue. |

#### How difficult gaps are recognized

Raw similarity distances from different parts of a playlist are not directly comparable because their preceding contexts differ. For a direct transition A -> B, B is compared with up to **Musical context window** preceding songs ending in A. Better Call Bliss therefore builds one frozen reference distribution before adding anything.

At every position in the selected source route, it scores original source songs that are not in that position's context against that context. The sorted source-to-context distances become the job's scale. A percentile means "how this distance compares with many alternatives drawn from the original playlist." It is not percentage similarity, and the reference is not built from the complete music library.

An original gap is eligible only when its direct distance is above **Bridge trigger percentile**. See [Understanding transition-quality percentiles](#understanding-transition-quality-percentiles) for how this shared lower-is-stricter setting differs from the destination-routing reference scale.

#### How candidates are chosen for one gap

Candidate discovery starts again for each transition in the selected-or-preserved source-only route. The local endpoints and preceding route context determine acoustic suitability. The complete source set does **not** become a single acoustic mood-board input here; it is used to build the common percentile scale and, only when endpoint-local Last.fm evidence is empty, to supply collection-level artist fallback.

For a gap A -> B, optional Last.fm evidence has this order of strength:

1. **Track-similar to both A and B:** recording evidence agrees on both sides of the gap.
2. **Track-similar to A or B:** one neighboring recording endorses the candidate.
3. **Endpoint-local similar artist:** Last.fm relates the candidate's artist to A's or B's artist.
4. **Collection artist fallback:** used only when the gap has no endpoint-local track or artist evidence; the candidate's artist may relate to any artist in the complete original playlist.
5. **Bliss only:** a candidate without Last.fm evidence remains eligible.

The plugin asks LastMix about every distinct track and artist in the original playlist, using anonymous `track.getSimilar` and `artist.getSimilar` access, and retains at most the first 25 valid results from each request. A source recording's Lyrion MBID is used for the LastMix request when available, with LastMix falling back to artist and title. Returned recordings currently resolve to analyzed local candidates by normalized artist and title; their returned MBIDs are also retained in the frozen evidence. Last.fm's match score, rank, identity confidence, and the exact source relationship are frozen with them.

Last.fm never replaces the candidate library. Every candidate still comes from the frozen intersection of usable Bliss rows and current local LMS tracks. If the pool contains more than 256 tracks, up to 32 strongest semantic matches are reserved while acoustic shortlisting fills the remaining positions. Bliss then evaluates both legs, repeat safety, and improvement. Rejected candidates stay rejected regardless of Last.fm evidence.

All per-gap shortlists are prepared from the frozen source-only route before any bridge is inserted. During left-to-right selection, shortlisted candidates are scored again against the evolving route. An earlier bridge can therefore change a later gap's preceding tracks and final contextual score, but cannot add new candidates to that later gap's shortlist. Inside the current gap, **Adaptive gap context** controls whether those evolving tracks also cause the feature-weight matrix itself to be recalculated.  

Among candidates that pass those checks, the two job percentages provide a bounded adjustment to the acoustic worst-leg and detour rankings. Evidence strength uses Last.fm's match score when present, otherwise its result rank, and is reduced for uncertain identity matches. Support from both recordings is stronger than support from one; collection-level artist evidence is weaker than endpoint-local artist evidence. The combined adjustment is capped at ten percentile points. Therefore 100% means maximum permitted guidance, not "let Last.fm choose," while 0% completely ignores that evidence type.

#### How a bridge is tested

For C inserted between A and B, the track context always evolves:  

- **Left leg:** compare C with up to N preceding tracks ending in A.  
- **Right leg:** insert C, then compare B with the updated preceding context ending in C.  

N is **Musical context window**. With N = 3 and a route ending W -> X -> A -> B, the left context is W, X, A and the candidate is C. For the second leg the context becomes X, A, C and the candidate is B. W drops out of the window.  

The option changes how Adaptive turns those context tracks into feature weights:  

- **Follow the evolving route:** the left leg derives its Adaptive matrix from W, X, A. After C is inserted, the right leg derives another matrix from X, A, C. Both the context average and the feature weights evolve.  
- **Freeze weights per source gap:** the matrix is derived once from W, X, A and reused for both legs. The right leg still uses the updated context average X, A, C, and C still participates in repeat checks; only the feature weights remain fixed. If a native request places several tracks in the same original gap, that one matrix governs all of its legs.  

Static scoring has one configured matrix already, so the selector is hidden for Static jobs. The optimizer records the selected context policy, seed policy, configured and effective learned shares, learned-matrix availability, base matrix identity, and fallback policy in every route or bridge result. Better Call Bliss shows a concise summary and writes fuller details at information/debug log levels.  

~~~mermaid
flowchart LR
    P["... W -> X -> A"] --> C["candidate C"]
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

The source-only gaps of the frozen base route are processed from left to right. A bridge selected earlier becomes part of the preceding context used to score later shortlisted candidates. It does not cause Last.fm to be queried again, rebuild a later shortlist, change the complete-source fallback, or import candidates outside the frozen eligible pool.

The best admissible candidate is inserted only if its local objective improves on the direct gap:

    (left distance + right distance) + 2 x max(left distance, right distance)
        < direct distance + 2 x direct distance

Processing stops at **Maximum additional tracks**. A gap below the trigger, a depleted budget, a repeat conflict, failed acoustic gates, or no genuine improvement remains unchanged.

~~~mermaid
flowchart LR
    P["Current playlist segment<br/>W -> X -> A -> B"] --> G["Improve local gap A -> B"]
    C["Eligible tracks<br/>C, D, E, ..."] --> G
    S["Whole source set<br/>scale and fallback only"] -.-> G
    G --> R["Possible result<br/>W -> X -> A -> +C -> B"]
~~~

### Extend playlist

Use **Extend playlist** when the playlist should become larger by a chosen amount. This is the everyday "please add N more songs" workflow: if you ask for 20 additions, Better Call Bliss tries to add 20 local analyzed songs. It is not capped by the number of gaps between the source tracks.

For addition similarity, Extend playlist uses a complete-source-set membership model. Every original track is retained exactly once and all original tracks together form one fixed acoustic relevance context while additions are selected. Source order does not change that membership reference: Optimize and Preserve initially discover the same candidates from the same source set. They differ only after membership selection, when the tracks are arranged.

Each eligible library track receives one relevance distance to that complete source context. It is not tested as a bridge between a particular pair. Newly selected songs do not become new relevance inputs, so candidate 1 cannot pull candidate 2 toward a new style. Optional Last.fm track and artist relationships from every original source track can support ranking inside the Bliss-qualified pool, but do not replace that acoustic relevance result.

Use **Add exactly N tracks** or **Double the track count** when the source is already an existing playlist and you know how many songs it should gain. Use **Reach a final track count** when you want to expand a short seed list, mood board, or queue snapshot to a chosen size. After membership is chosen, **Source-track order** decides placement: Optimize may route the enlarged set freely, while Preserve keeps the original songs as ordered anchors and places additions around them when the repeat windows can be satisfied.

The **Chosen amount** selector has three count-based variants:

- **Add exactly N tracks:** final size is `S + N`.
- **Reach a final track count:** final size is the entered target `T`; additions are `T - S`.
- **Double the track count:** final size is `2S`; additions are `S`.

These variants use exactly the same candidate-discovery and ranking process. They differ only in the number of additions requested.

Duration-based targets remain future work. Advanced strict gap-bridge placement is a separate planned mode, because it answers a different question: "put bridge routes inside source gaps" rather than "make this playlist larger."

#### Options for Extend playlist

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Source-track order | Optimize by default | Optimize routes the complete extended set freely. Preserve keeps source tracks as ordered anchors and places additions around them. |
| Chosen amount | Exact additions, final track count, or double count | Defines the requested final size. |
| Exact number of additions | 1-100; default 1 | Used only by Add exactly N tracks. It is not limited by `S - 1` gaps. |
| Final track count | 3-500; default 25 | Used only by Reach final track count. Must be greater than `S`. |
| Musical context window | 1-50; inherited from BlissMixer | Controls final route ordering only. Membership relevance always uses every original source track. |
| Learned-matrix blend | 0-100%; inherited from BlissMixerExt when available | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0-10,000; inherited | Limits artist membership capacity and constrains the final route. Zero disables it. |
| Album look-back | 0-10,000; inherited | Limits album membership capacity and constrains the final route. Zero disables it. |
| Additional route-search attempts | 0-500; default 50 | Applies only when Source-track order is Optimize. |
| Variation | 0-100%; default 25 | Varies the added membership and final route inside a bounded high-quality pool. |
| Generation seed | 0-4,294,967,295; generated by default | Reproduces both membership selection and final ordering. |
| Use Last.fm guidance | Inherited; optional | Enables failure-tolerant track and artist evidence through LastMix. |
| Similar-track guidance | 0-100%; inherited from BlissMixerExt | Bounded support from recording relationships while ranking local candidates. Better Call Bliss reads the current BlissMixerExt value and falls back to 25 when needed. |
| Similar-artist guidance | 0-100%; default 25 | Bounded support from artist relationships while ranking local candidates. |
| Output | Choose after preview | Preview is read-only. Accepting the preview can create a verified copy, overwrite the source with confirmation, or send the result to a player queue. |

#### How Extend playlist chooses additions

Extend playlist uses the native fixed-source extension request for membership selection. The former separate target-size mode was removed because it duplicated **Reach a final track count**. The optimizer ranks current LMS-local Bliss candidates against one fixed whole-source acoustic context using the effective Bliss scoring configuration. All originals are evidence, while selected additions are not fed back as new evidence. Repeat-window capacity is applied during membership selection, and every selected addition must still resolve to the current LMS library before the result can be accepted.

When Variation or Last.fm guidance is active, only a bounded top-quality acoustic pool is diversified or semantically adjusted first. Candidates below that pool remain ordered acoustic fallbacks for satisfying repeat-window capacity; Last.fm cannot pull an acoustically distant track into the preferred pool. Artist and album capacity is checked while the requested membership is assembled. Only after the exact membership exists does route placement begin.

This means Extend playlist behaves like users expect from an extension feature: the chosen count is a real count request. It can still fail, but failures should be about real constraints such as insufficient repeat-safe local candidates, missing Bliss analysis, or a target larger than the supported 500-track request limit - not merely because the original playlist has too few internal gaps.

~~~mermaid
flowchart LR
    S["Source playlist<br/>A -> B -> C"] --> C["Choose N additions<br/>against A + B + C"]
    L["Eligible tracks<br/>X, Y, Z, ..."] --> C
    F["Optional Last.fm"] -.-> C
    C --> M["Chosen membership<br/>A, B, C, +X, +Y"]
    M --> P["Preserve result<br/>A -> +X -> B -> +Y -> C"]
    M --> O["Optimize result<br/>+Y -> B -> A -> +X -> C"]
~~~


## Similarity supplied by BlissMixer

BlissMixer also already owns an immediate mix-generation action, **Create bliss mix**. Better Call Bliss credits that feature and treats it as related prior work: BlissMixer creates playable Bliss mixes directly from a selected track, artist, album, or genre, while Better Call Bliss focuses on previewable, auditable playlist and queue transformations before anything is saved or sent to a player.

Similarity scoring is an input to the playlist workflows above, not Better Call Bliss's main feature. The workflow chooses the candidate and the tracks that form its comparison context first; Adaptive or Static then measures the candidate against exactly those inputs. A mixing strategy does not independently scan the library, choose gap endpoints, turn an added song into a seed, or decide where a selected song is placed.

The base strategy and settings come from the original [BlissMixer](https://github.com/CDrummond/lms-blissmixer). Better Call Bliss requires a compatible original BlissMixer installation and reuses the shared native Bliss scoring core so both applications interpret the 23 Bliss audio features consistently. Optional learned personalization comes from [BlissMixerExt](https://github.com/chrober/lms-blissmixer-ext), which owns `learned_matrix.json`, its learned-blend preference, and the durable Last.fm similar-track guidance preference. Better Call Bliss consumes that current track-guidance value instead of storing another global copy.

**Adaptive dynamic weighting** and **Static weighted distance** are connected in Better Call Bliss. Extended Isolation Forest remains a BlissMixer capability for now; its Better Call Bliss option is visible but disabled until native playlist-routing semantics are implemented.

### Adaptive dynamic weighting  -  working

Adaptive behaves like a DJ who listens for the common thread in the music immediately before the next song. If those songs share a rhythmic feel, rhythm becomes an important clue. If they instead share a similar tone or harmony, Adaptive follows that clue. The important qualities can change as the playlist develops.

**Musical context window** tells it how many previous songs to consider. A value of 3 means "judge the next song using up to the previous three songs." Near the beginning, it uses the smaller context available.

#### Options for Adaptive scoring

| Option | Range / default | Effect |
| --- | --- | --- |
| Musical context window | 1-50; inherited from BlissMixer | Maximum preceding tracks used for each directional route or bridge score. Extend membership deliberately uses the complete original source set instead. |
| Learned-matrix blend | 0-100%; inherited from BlissMixerExt when available | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |

#### How Adaptive calculates distance

Each analyzed track has the same 23-feature Bliss vector: tempo, timbre, loudness, and chroma measurements.

For a non-empty context:

1. The optimizer calculates the arithmetic mean of the context vectors. This is the target sound.
2. With two or more context tracks, it derives a variance-based matrix. Features on which those tracks agree receive more influence; features on which they differ receive less.
3. It blends that matrix with the learned Mahalanobis matrix using **Learned-matrix blend**.
4. It calculates the Mahalanobis distance from the candidate vector to the context mean. Smaller means a closer fit.

With one context track, variance cannot be derived from the context. If a learned matrix is available, Better Call Bliss uses it for that one-track distance. If it is absent, the optimizer falls back to the same Static BlissMixer feature-weight matrix used by the explicit Static strategy.

Distance is directional because the context comes from the proposed route prefix. A -> B and B -> A need not receive the same score.

#### Is a learned matrix optional?

For Better Call Bliss and the shared Adaptive algorithm, **yes**. BlissMixerExt optionally produces the learned matrix through its similarity survey and training process:

- with two or more context tracks and no learned matrix, Adaptive can use the variance-based matrix by itself;
- with two or more context tracks and a learned matrix, **Learned-matrix blend** combines the learned and variance-based matrices;
- with one context track, no variance matrix can be calculated; the shared scoring path falls back to the Static BlissMixer weights when the learned matrix is absent.

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
    F --> G["Route, bridge or extension<br/>decision uses that distance"]
~~~


### Extended Isolation Forest  -  planned for Better Call Bliss

Forest mode uses several example songs to learn the broad sound they share, then favors songs that fit that group and treats outsiders as less suitable.

Bringing it into playlist routing still requires decisions about the minimum context near the start of a route, fallback behavior, when to rebuild a model after a route change, and how to score both sides of a bridge. Better Call Bliss therefore disables it instead of silently substituting another scorer.

## Behavior shared across workflows

The workflow tables omit **Track look-back** because every current workflow already requires unique playlist membership. Its compatibility value is retained in requests and result proofs, but changing it cannot alter the generated playlist today.

### Variation and reproducibility

Variation asks Better Call Bliss to explore different qualified answers. It does not change Bliss features, similarity matrices, repeat windows, or bridge acceptance gates.

For movable routes, a generated or supplied seed changes the greedy restart paths. Zero uses a fixed baseline seed; any positive value uses the job's generation seed.

For Extend playlist, the percentage additionally controls membership sampling inside the quality pool. Higher values flatten the acoustic weighting and make lower-ranked qualified candidates more likely.

For difficult-transition bridges, Variation reproducibly reorders a bounded pool of candidates that passed the acoustic gate. For **Bliss me there...**, it chooses among complete routes inside the current result's narrow quality band; this includes bounded best-effort routes when no permitted path reaches the requested target. It does not relax leg percentiles, uniqueness, repeat windows, or the fixed destination. A preserved source route can still return the same result when only one candidate qualifies.

A recorded generation seed reproduces the same request and result across worker counts when the library, artifacts, and options are unchanged.

### Last.fm track and artist guidance

Last.fm is an optional guide for choosing new songs. It never replaces Bliss similarity and never causes a non-local or otherwise invalid track to be admitted.

Better Call Bliss uses the installed LastMix plugin without user credentials. It requests similar tracks once for every distinct original recording and similar artists once for every distinct original artist. Recording relationships are endpoint-local. Artist relationships are recorded both for endpoint-local use and for the complete original collection fallback.

The per-job **Similar-track guidance** and **Similar-artist guidance** controls range from 0 to 100. Similar-track guidance starts with the current BlissMixerExt preference; when BlissMixerExt 0.3.0 or newer is unavailable, Better Call Bliss safely falls back to 25. Similar-artist guidance remains a Better Call Bliss default of 25. Both can be overridden for one job without changing either plugin's global settings. They scale a bounded supporting signal after locality, repeat, and Bliss acoustic qualification. Even 100 cannot make a rejected acoustic candidate acceptable. Zero ignores that evidence type without disabling the other one.

Bridge modes use the signal to rank admissible two-leg insertions. Extend playlist uses track and artist evidence from the complete immutable source set to support membership ranking inside its Bliss-qualified pool. Last.fm has no effect on fixed-membership Reorder only jobs.

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

Preview writes no playlist. Only the separate user-confirmed action invokes Lyrion's playlist serializer and verifies the saved file and catalog order.
