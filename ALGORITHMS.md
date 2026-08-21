# Playlist optimization modes and options

Better Call Bliss turns a saved playlist or player-queue snapshot into a smoother listening experience. You decide whether existing songs may move, whether new songs may be added, and how much freedom the optimizer has. Playlist and queue-editor jobs preview the result, and nothing is changed until you accept it. The track-context **Bliss me there...** shortcut is intentionally different: it runs in the background and appends a successful route automatically.

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
| Append a fluent path from the current queue to a chosen song | [Bliss me there...](#bliss-me-there) from a track context menu | The current queue tail and chosen track stay fixed. Better Call Bliss builds the route in the background and automatically appends its intermediates and destination when every check succeeds. |

Three job choices work together:

1. **Source-track order** decides whether songs already in the playlist may move.
2. **Additional tracks** asks for the listener-facing purpose: no additions, improve difficult transitions, or extend the source by a chosen amount. **Extend playlist** opens the second **Chosen amount** selector for exact additions, final track count, or double track count; **Reach a final track count** is also the replacement for the former separate target-size workflow.
3. **Mixing strategy** supplies the similarity measurement used by those playlist operations. Better Call Bliss reuses this capability from BlissMixer; it is not the main feature being selected here.

## Features at a glance

### Playlist operations

| Choice | Status | Best when... | What changes |
| --- | --- | --- | --- |
| [Optimize source order](#reorder-existing-tracks-only) | Working | The songs are right, but the order is not. | Existing songs may move; the membership stays the same unless an addition mode is also selected. |
| [Preserve source order and fill gaps](#preserve-source-order-and-fill-gaps) | Working | The current order matters: chronology, story, album-like flow, or deliberate DJ arc. | Existing songs stay in their current order; additions can be placed around those anchors. |
| [No additions / reorder existing tracks only](#reorder-existing-tracks-only) | Working | You want a cleaner sequence without changing the track list. | No new tracks are added; no source tracks are removed. |
| [Improve difficult transitions](#add-automatically) | Working | The playlist mostly works, but a few handovers are awkward. | Adds zero or more bridge tracks only where the frozen source route has difficult transitions. |
| [Extend playlist](#extend-playlist) | Working | The playlist is already the thing you want, just too short. | Adds a chosen amount of local songs. Addition similarity is based on the complete original source set, not on one gap at a time; originals remain required members. |
| [Bliss me there...](#bliss-me-there) | Working | A player queue already has a tail and you want to arrive at one selected local track smoothly. | Runs a destination-locked route in the background, rechecks the live queue tail, and automatically appends zero or more intermediates plus the destination. |
| Add N bridge tracks per source transition | Planned | You want a strict "put the same number of bridges inside every existing gap" placement rule. | Future preset; different from Extend playlist because the number of additions is tied to each source transition. |
| Duration target | Planned | You want "make this about 90 minutes" rather than "make this 30 tracks." | Future target unit; track-count targets already work through Extend playlist. |

### Similarity and evidence inputs

| Choice | Status | Role |
| --- | --- | --- |
| [Adaptive dynamic weighting](#adaptive-dynamic-weighting--working) | Working | BlissMixer's adaptive similarity measurement for each decision. |
| [Static weighted distance](#static-weighted-distance--working) | Working | BlissMixer's fixed user priorities. |
| [Extended Isolation Forest](#extended-isolation-forest--planned-for-better-call-bliss) | Planned | BlissMixer's model of the sound shared by several example songs. |
| [Last.fm track and artist guidance](#lastfm-track-and-artist-guidance) | Working, optional | Extra evidence for ranking suitable additions; Bliss remains the acoustic gate. |

## How the pieces fit together

The Better Call Bliss plugin resolves Lyrion tracks, reads per-job options, freezes the LMS-local candidate inventory, and optionally asks LastMix for Last.fm track and artist relationships. The native [bliss-playlist-optimizer](https://github.com/chrober/bliss-playlist-optimizer) performs scoring and bounded search. Only the plugin writes playlists or player queues. Editor jobs require explicit acceptance; **Bliss me there...** automatically appends only after its background route and live-tail checks succeed.

## Bliss me there

Use this from a local track's context menu when a player already has something in its queue and you want to arrive at the selected song smoothly. The action closes the context menu and starts a background job with the saved **Bliss me there...** defaults. It does not open the Extras page and does not require a separate Accept button. A successful result is appended automatically; the job remains visible under **Running and recent previews** for status or error review.

The current queue tail is the fixed start and the selected song is the fixed destination. Recent local queue tracks before the tail are captured as acoustic and repeat context; they are not appended again. Better Call Bliss may place local analyzed tracks between the two anchors. When the job succeeds, only those intermediates and the destination are appended.

**Choose automatically** first measures the actual tail-to-destination edge. With a minimum of zero, it may use that direct edge when it meets the target. When Adaptive and a learned matrix are available, Better Call Bliss checks that jump through both the learned view and the current Static BlissMixer weights. The view that considers the direct jump more difficult governs the complete route. This protects against a specialized learned matrix declaring a musically abrupt jump safe merely because it is close along the dimensions that matrix emphasizes. Otherwise, a dedicated layered search builds complete paths from **Minimum intermediate tracks** through **Maximum intermediate tracks**. It ranks paths by their worst neighboring Bliss distance and then by the sum of all neighboring distances. Automatic chooses the shortest permitted path that genuinely meets the adjacent percentile target; if none does, it returns the smoothest repeat-safe permitted best effort. **Use an exact count** runs the same adjacent path search for precisely the requested number of intermediates and remains all-or-nothing.  

Candidate discovery remains bounded: endpoint Last.fm evidence and the original tail-to-destination acoustic gap produce a local shortlist under the governing acoustic view, then the layered search explores different complete paths through that graph. For every final adjacent `A -> B` edge, the optimizer ranks the fixed-matrix distance against `A -> every current LMS-local analyzed track` under the same matrix. The result identifies the governing learned-matrix or Static-weight role and hash, records the direct-edge verdict from both views when both exist, and reports every edge, the route sum, raw bottleneck, and worst adjacent percentile. Earlier queue-context edges are not included in this destination-path quality result.  

The destination is explicit user intent, so a conflict already present solely between recent immutable queue context and that destination does not reject the job. Every generated intermediate remains unique and is checked against the destination and all other tracks inside the configured artist, album, and track windows. Last.fm similar-track and similar-artist evidence supports candidate ranking, but Bliss remains the primary path-quality evidence. Variation is applied only among complete routes inside a narrow quality band, so it can change a reproducible choice without relaxing repeat rules or turning a clearly worse route into a candidate.  

Before appending, Better Call Bliss compares the live queue tail with the captured tail. Normal playback advancing through existing queue entries does not invalidate the job, because the queue tail is unchanged. If another controller changes the end of the queue, the result is refused and nothing is appended. Existing queue entries are never removed or reordered by this action.

#### Options for Bliss me there

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Intermediate tracks | Automatic or Exact; saved plugin default | Automatic chooses the shortest complete path that meets the adjacent target, or the smoothest bounded best effort. Exact requires precisely the requested count. Both use the same dedicated adjacent path search. |
| Search effort | Fast; Balanced; Thorough; default Fast | Controls how many local candidates and partial paths are explored. Fast deliberately bounds the search; Balanced and Thorough trade more time and memory for a wider search. It never relaxes the quality target or repeat rules. |
| Minimum intermediate tracks | 0-8; default 0 | Lower bound used only by Automatic. Zero allows a direct transition; a positive value forces Automatic to insert at least that many tracks. It must not exceed the maximum. |
| Maximum intermediate tracks | 0-8; default 4 | Upper bound used only by Automatic. It is also the budget for the best-effort comparison. Zero means direct-only. |
| Exact intermediate tracks | 0-8; default 2 | Count used only by Exact. Zero explicitly requests the direct destination. |
| Transition quality target percentile | 0-100%; plugin default | Desired maximum source-relative percentile of the worst actual neighboring transition. The same value still decides whether the direct edge needs intervention; separate trigger and target controls remain planned. |
| Musical context window | 1-50; inherited from BlissMixer | Helps build the bounded initial candidate evidence from recent queue context. It does not change the fixed pairwise adjacent objective or final destination-path report. |
| Mixing strategy and learned blend | Inherited from BlissMixer | Uses Adaptive or Static scoring. A learned matrix remains optional. |
| Artist, album, and track look-back | Inherited from BlissMixer | Hard constraints for generated intermediates; zero disables a window. The chosen destination itself remains fixed user intent. |
| Variation and generation seed | 0-100%; default 25 | Chooses reproducibly among complete routes close to the best adjacent bottleneck and route sum. Zero keeps the strict deterministic winner. |
| Last.fm track/artist guidance | Optional; defaults 25% each | Provides bounded supporting evidence for candidates related to the tail, destination, or captured context. Provider failure falls back to Bliss. |
| Output | Automatic background append | The action is locked to the source player and appends only intermediates plus destination after route and live-tail validation. It never clears or replaces existing queue entries. |

#### How the destination route is chosen

~~~mermaid
flowchart TD
    A["Track context action"] --> B["Start background job with saved defaults"]
    B --> C["Capture current queue tail<br/>and recent local context"]
    C --> D["Lock selected destination"]
    D --> E["Build Bliss and optional<br/>Last.fm candidate evidence"]
    E --> V["Compare learned and Static<br/>direct-edge risk when available"]
    V --> W["Use the more cautious view<br/>for discovery and path quality"]
    W --> F{"Automatic or Exact?"}
    F -- Automatic --> G{"Minimum is zero and<br/>direct adjacent edge meets target?"}
    G -- Yes --> K["Route contains destination only"]
    G -- No --> H["Search every permitted count<br/>with selected effort"]
    H --> I{"Any complete path meets target?"}
    I -- Yes --> P["Choose shortest qualifying path"]
    I -- No --> Q["Choose smoothest repeat-safe best effort"]
    F -- Exact --> L["Search the required count<br/>with the same adjacent objective"]
    L -- Not found --> J["Fail job; append nothing"]
    L -- Found --> R
    K --> R["Report every destination-path edge<br/>with matching local reference"]
    P --> R
    Q --> R
    R --> M{"Live queue tail unchanged?"}
    M -- Yes --> N["Append intermediates + destination"]
    M -- No --> O["Fail stale job; append nothing"]
~~~

## Overall workflow

~~~mermaid
flowchart TD
    P["Saved Lyrion playlist<br/>original source tracks"] --> O["Per-job ordering,<br/>extension, scoring,<br/>repeat and variation options"]
    DB[("bliss.db<br/>23 features per analyzed track")] --> I["Intersect Bliss rows with<br/>current local LMS library"]
    M["optional learned_matrix.json<br/>personalized Adaptive blend"] --> N
    O --> N["Native optimizer request"]
    I --> N
    L["Optional LastMix<br/>track and artist relationships"] --> N
    N --> S["Choose source route<br/>or preserve anchors"]
    S --> X{"Additional-track purpose"}
    X -- None --> R["Final route"]
    X -- Improve difficult transitions --> B["Gap-specific bridge search"]
    X -- Extend playlist --> G["Complete-source relevance search<br/>then final route search"]
    B --> R
    G --> R
    R --> V["Result artifact and proofs"]
    V --> Q["Read-only Preview"]
    Q -->|"user accepts"| W["Lyrion playlist or queue writer"]
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
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0-10,000; inherited | Forbids the same artist within that many preceding positions. Zero disables it. |
| Album look-back | 0-10,000; inherited | Forbids the same album within that many preceding positions. Zero disables it. |
| Additional route-search attempts | 0-500; default 50 | Adds seeded greedy starting routes. Zero still evaluates the built-in starts. |
| Variation | 0-100%; default 25 | Zero uses a fixed baseline route seed; any positive value uses the job's generation seed. |
| Generation seed | 0-4,294,967,295; generated by default | When Variation is positive, reusing the reported seed reproduces the same search. |
| Output | Choose after preview | Preview is read-only. Accepting the preview can create a verified copy, overwrite the source with confirmation, or send the result to a player queue. |

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

    sum of all transition distances + 2 x the worst transition

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

For example, A -> B -> C can become A -> X -> B -> Y -> C, but never B -> A -> C. This is useful for chronological playlists, albums, stories, or any sequence whose order already matters to you.

#### Options for Preserve source order

Preserve is an ordering policy used with **Improve difficult transitions** or **Extend playlist**. The chosen addition workflow supplies its remaining controls.

| Option | Range / default | Effect with preserved anchors |
| --- | --- | --- |
| Source-track order | Preserve | Keeps every original track as an immutable ordered anchor. |
| Musical context window | 1-50; inherited from BlissMixer | Controls the preceding context used for direct gaps and both legs of an inserted bridge. |
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0-10,000; inherited | Applied to the source-anchor pre-check and final route. Zero disables it. |
| Album look-back | 0-10,000; inherited | Applied to the source-anchor pre-check and final route. Zero disables it. |
| Use Last.fm guidance | Inherited; optional | Asks LastMix for track and artist relationships. Failures transparently use Bliss alone. |
| Similar-track guidance | 0-100%; default 25 | Bounded influence of recording-level evidence from the neighboring source tracks. Zero ignores it. |
| Similar-artist guidance | 0-100%; default 25 | Bounded influence of endpoint-local artist evidence, with the complete original artist set as fallback. Zero ignores it. |
| Output | Choose after preview | Preview is read-only. Accepting the preview can create a verified copy, overwrite the source with confirmation, or send the result to a player queue. |

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

In the current Extras UI this appears as **Improve difficult transitions when useful**.

Better Call Bliss first decides the order of the original songs - or respects your order if you chose Preserve. It then listens to each handover and asks: "Is this one of the awkward changes, and can one extra song genuinely improve it?"

The similarity base is local to the transition being repaired. Suppose the playlist contains A followed by B. A candidate C is used only if A -> C and C -> B both work, using the configured preceding context around that gap. It is not enough for C to resemble only A, only B, or the playlist in general. Last.fm guidance follows the same shape: similar-track evidence from A and B is strongest, endpoint artist evidence comes next, and the complete source artist pool is only a fallback when the local gap has no usable evidence.

If the original transition is already fine, or no candidate improves it safely, nothing is inserted. Therefore **Add automatically** can correctly add zero songs. This mode improves difficult transitions; it is not yet the repeat-window spacer-repair mode that can insert several tracks solely to separate repeated artists or albums.

#### Options for Add automatically

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Source-track order | Optimize by default | Either optimizes the originals before gap repair or preserves them as anchors. |
| Musical context window | 1-50; inherited from BlissMixer | Controls the preceding context for direct gaps and both candidate legs. |
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0-10,000; inherited | Rejects tentative and final routes with artists too close together. Zero disables it. |
| Album look-back | 0-10,000; inherited | Rejects tentative and final routes with albums too close together. Zero disables it. |
| Additional route-search attempts | 0-500; default 50 | Applies only when source order is Optimize. |
| Variation | 0-100%; default 25 | Can vary the optimized source route; it has no separate random bridge-selection step. |
| Generation seed | 0-4,294,967,295; generated by default | Reproduces the optimized source route when source order may move. |
| Use Last.fm guidance | Inherited; optional | Enables failure-tolerant track and artist evidence through LastMix. |
| Similar-track guidance | 0-100%; default 25 | Bounded support from tracks related to A, B, or both. Zero ignores recording evidence. |
| Similar-artist guidance | 0-100%; default 25 | Bounded support from related endpoint artists or, when no local evidence exists, the original artist collection. Zero ignores artist evidence. |
| Maximum additional tracks | 0-100; default 8 | Stops insertion after this many bridges. |
| Bridge trigger percentile | 0-100%; default 70 | Considers only original gaps above this point on the frozen reference scale. |
| Output | Choose after preview | Preview is read-only. Accepting the preview can create a verified copy, overwrite the source with confirmation, or send the result to a player queue. |

#### How difficult gaps are recognized

Raw similarity distances from different parts of a playlist are not directly comparable because their preceding contexts differ. For a direct transition A -> B, B is compared with up to **Musical context window** preceding songs ending in A. Better Call Bliss therefore builds one frozen reference distribution before adding anything.

At every position in the selected source route, it scores original source songs that are not in that position's context against that context. The sorted source-to-context distances become the job's scale. A percentile means "how this distance compares with many alternatives drawn from the original playlist." It is not percentage similarity, and the reference is not built from the complete music library.

An original gap is eligible only when its direct distance is above **Bridge trigger percentile**.

#### How candidates are chosen for one gap

For a gap A -> B, optional Last.fm evidence has this order of strength:

1. **Track-similar to both A and B:** recording evidence agrees on both sides of the gap.
2. **Track-similar to A or B:** one neighboring recording endorses the candidate.
3. **Endpoint-local similar artist:** Last.fm relates the candidate's artist to A's or B's artist.
4. **Collection artist fallback:** used only when the gap has no endpoint-local track or artist evidence; the candidate's artist may relate to any artist in the complete original playlist.
5. **Bliss only:** a candidate without Last.fm evidence remains eligible.

The plugin asks LastMix about every distinct track and artist in the original playlist, using anonymous `track.getSimilar` and `artist.getSimilar` access, and retains at most the first 25 valid results from each request. A source recording's Lyrion MBID is used for the LastMix request when available, with LastMix falling back to artist and title. Returned recordings currently resolve to analyzed local candidates by normalized artist and title; their returned MBIDs are also retained in the frozen evidence. Last.fm's match score, rank, identity confidence, and the exact source relationship are frozen with them.

Last.fm never replaces the candidate library. Every candidate still comes from the frozen intersection of usable Bliss rows and current local LMS tracks. If the pool contains more than 256 tracks, up to 32 strongest semantic matches are reserved while acoustic shortlisting fills the remaining positions. Bliss then evaluates both legs, repeat safety, and improvement. Rejected candidates stay rejected regardless of Last.fm evidence.

Among candidates that pass those checks, the two job percentages provide a bounded ranking adjustment. Evidence strength uses Last.fm's match score when present, otherwise its result rank, and is reduced for uncertain identity matches. Support from both recordings is stronger than support from one; collection-level artist evidence is weaker than endpoint-local artist evidence. The combined adjustment is capped at ten percentile points. Therefore 100% means maximum permitted guidance, not "let Last.fm choose," while 0% completely ignores that evidence type.

#### How a bridge is tested

For C inserted between A and B:

- **Left leg:** compare C with up to N preceding tracks ending in A.
- **Right leg:** insert C, then compare B with the updated preceding context ending in C.

N is **Musical context window**. With N = 3 and a route ending W -> X -> A -> B, the left context is W, X, A and the candidate is C. For the second leg the context becomes X, A, C and the candidate is B. W drops out of the window.

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

Original gaps are processed from left to right. A bridge selected earlier becomes part of the preceding context used to score later bridge candidates.

The best admissible candidate is inserted only if its local objective improves on the direct gap:

    (left distance + right distance) + 2 x max(left distance, right distance)
        < direct distance + 2 x direct distance

Processing stops at **Maximum additional tracks**. A gap below the trigger, a depleted budget, a repeat conflict, failed acoustic gates, or no genuine improvement remains unchanged.

~~~mermaid
flowchart TD
    A["Selected or preserved source route"] --> B["Build frozen source-based<br/>distance distribution"]
    B --> C["Inspect original gaps<br/>from left to right"]
    C --> D{"Direct gap above trigger?"}
    D -- No --> N["Leave gap unchanged"]
    D -- Yes --> E["Choose endpoint-local,<br/>collection fallback or<br/>Bliss-only pool"]
    E --> F["Shortlist at most 256 tracks"]
    F --> G["Score context-ending-A -> C"]
    G --> H["Insert C into context<br/>and score -> B"]
    H --> I{"Unique, repeat-safe,<br/>both gates pass and<br/>local objective improves?"}
    I -- No --> N
    I -- Yes --> J["Insert best bridge"]
    J --> K{"Budget or gaps exhausted?"}
    N --> K
    K -- No --> C
    K -- Yes --> R["Return result and decisions"]
~~~

### Extend playlist

Use **Extend playlist** when the playlist should become larger by a chosen amount. This is the everyday "please add N more songs" workflow: if you ask for 20 additions, Better Call Bliss tries to add 20 local analyzed songs. It is not capped by the number of gaps between the source tracks.

For addition similarity, Extend playlist uses a complete-source-set membership model. Every original track is retained exactly once and the complete source set stays the fixed musical reference while additions are selected. In other words, added tracks are chosen because they fit the original playlist or seed list as a whole, not because they bridge one specific A -> B gap. Newly selected songs do not pull the next choices away from the original taste.

Use **Add exactly N tracks** or **Double the track count** when the source is already an existing playlist and you know how many songs it should gain. Use **Reach a final track count** when you want to expand a short seed list, mood board, or queue snapshot to a chosen size. After membership is chosen, **Source-track order** decides placement: Optimize may route the enlarged set freely, while Preserve keeps the original songs as ordered anchors and places additions around them when the repeat windows can be satisfied.

The **Chosen amount** selector has three count-based variants:

- **Add exactly N tracks:** final size is `S + N`.
- **Reach a final track count:** final size is the entered target `T`; additions are `T - S`.
- **Double the track count:** final size is `2S`; additions are `S`.

Duration-based targets remain future work. Advanced strict gap-bridge placement is a separate planned mode, because it answers a different question: "put bridge routes inside source gaps" rather than "make this playlist larger."

#### Options for Extend playlist

| Option | Range / default | Effect in this workflow |
| --- | --- | --- |
| Source-track order | Optimize by default | Optimize routes the complete extended set freely. Preserve keeps source tracks as ordered anchors and places additions around them. |
| Chosen amount | Exact additions, final track count, or double count | Defines the requested final size. |
| Exact number of additions | 1-100; default 1 | Used only by Add exactly N tracks. It is not limited by `S - 1` gaps. |
| Final track count | 3-500; default 25 | Used only by Reach final track count. Must be greater than `S`. |
| Musical context window | 1-50; inherited from BlissMixer | Controls final route ordering only. Membership relevance always uses every original source track. |
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |
| Artist look-back | 0-10,000; inherited | Limits artist membership capacity and constrains the final route. Zero disables it. |
| Album look-back | 0-10,000; inherited | Limits album membership capacity and constrains the final route. Zero disables it. |
| Additional route-search attempts | 0-500; default 50 | Applies only when Source-track order is Optimize. |
| Variation | 0-100%; default 25 | Varies the added membership and final route inside a bounded high-quality pool. |
| Generation seed | 0-4,294,967,295; generated by default | Reproduces both membership selection and final ordering. |
| Use Last.fm guidance | Inherited; optional | Enables failure-tolerant track and artist evidence through LastMix. |
| Similar-track guidance | 0-100%; default 25 | Bounded support from recording relationships while ranking local candidates. |
| Similar-artist guidance | 0-100%; default 25 | Bounded support from artist relationships while ranking local candidates. |
| Output | Choose after preview | Preview is read-only. Accepting the preview can create a verified copy, overwrite the source with confirmation, or send the result to a player queue. |

#### How Extend playlist chooses additions

Extend playlist uses the native fixed-source extension request for membership selection. The former separate target-size mode was removed because it duplicated **Reach a final track count**. The optimizer ranks current LMS-local Bliss candidates against one fixed Adaptive context built from the complete source set. All originals are evidence, while selected additions are not fed back as new evidence. Repeat-window capacity is applied during membership selection, and every selected addition must still resolve to the current LMS library before the result can be accepted.

This means Extend playlist behaves like users expect from an extension feature: the chosen count is a real count request. It can still fail, but failures should be about real constraints such as insufficient repeat-safe local candidates, missing Bliss analysis, or a target larger than the supported 500-track request limit - not merely because the original playlist has too few internal gaps.

~~~mermaid
flowchart TD
    A["Source playlist or queue snapshot"] --> B["Calculate requested final size"]
    B --> C["Build fixed source-set relevance reference"]
    C --> D["Rank current LMS-local Bliss candidates"]
    D --> E["Apply uniqueness and repeat-window capacity"]
    E --> F{"Enough additions found?"}
    F -- No --> X["Fail without partial output"]
    F -- Yes --> G["Combine originals and additions"]
    G --> H{"Source-track order"}
    H -- Optimize --> I["Route complete extended set freely"]
    H -- Preserve --> J["Keep originals as ordered anchors<br/>and place additions around them"]
    I --> R["Read-only preview"]
    J --> R
~~~


## Similarity supplied by BlissMixer

BlissMixer also already owns an immediate mix-generation action, **Create bliss mix**. Better Call Bliss credits that feature and treats it as related prior work: BlissMixer creates playable Bliss mixes directly from a selected track, artist, album, or genre, while Better Call Bliss focuses on previewable, auditable playlist and queue transformations before anything is saved or sent to a player.

Similarity scoring is an input to the playlist workflows above, not Better Call Bliss's main feature. The algorithms and learned-matrix capability come from the [BlissMixer implementation and its algorithm guide](https://github.com/chrober/lms-blissmixer/blob/main/ALGORITHMS.md). Better Call Bliss depends on a compatible lms-blissmixer installation and reuses the shared native Bliss scoring core so both applications interpret the 23 Bliss audio features consistently.

**Adaptive dynamic weighting** and **Static weighted distance** are connected in Better Call Bliss. Extended Isolation Forest remains a BlissMixer capability for now; its Better Call Bliss option is visible but disabled until native playlist-routing semantics are implemented.

### Adaptive dynamic weighting  -  working

Adaptive behaves like a DJ who listens for the common thread in the music immediately before the next song. If those songs share a rhythmic feel, rhythm becomes an important clue. If they instead share a similar tone or harmony, Adaptive follows that clue. The important qualities can change as the playlist develops.

**Musical context window** tells it how many previous songs to consider. A value of 3 means "judge the next song using up to the previous three songs." Near the beginning, it uses the smaller context available.

#### Options for Adaptive scoring

| Option | Range / default | Effect |
| --- | --- | --- |
| Musical context window | 1-50; inherited from BlissMixer | Maximum preceding tracks used for each directional route or bridge score. Extend membership deliberately uses the complete original source set instead. |
| Learned-matrix blend | 0-100%; inherited | Learned share for contexts with at least two tracks. If no learned matrix is available, multi-track contexts use pure variance and one-track contexts use Static BlissMixer weights. |

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

The per-job **Similar-track guidance** and **Similar-artist guidance** controls range from 0 to 100 and both default to 25. They scale a bounded supporting signal after locality, repeat, and Bliss acoustic qualification. Even 100 cannot make a rejected acoustic candidate acceptable. Zero ignores that evidence type without disabling the other one.

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
