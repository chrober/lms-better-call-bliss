# Better Call Bliss improvement backlog

This is a concise, re-orderable view of potential Better Call Bliss work.  
**Row order is the priority order:** move a complete row up or down to change
priority. The linked source remains authoritative for scope, rationale, and
acceptance criteria; this file intentionally does not duplicate those details.  

The **size** is a rough engineering estimate, not priority or elapsed time:
**S** is a contained plugin change, **M** spans one component with tests,
**L** crosses components or needs substantial verification, and **XL** changes
architecture, algorithms, or several repositories.  

| Improvement | Intended outcome | Size | Status | Authoritative source |
| --- | --- | ---: | --- | --- |
| Selectable Last.fm acquisition: **LastMix** or **API Key** | Let administrators choose the established LastMix integration or direct public Last.fm access with their own API key, while retaining identical Bliss-first guidance semantics. | XL | Approved design | [Last.fm guidance acquisition plan](https://github.com/chrober/bliss-similarity-design/blob/main/LASTFM_GUIDANCE_ACQUISITION_PLAN.md) |
| Direct Last.fm provider cache and offline behaviour | Provide durable cache freshness, stale-offline policy, timeouts, rate limits, cancellation, and clear diagnostics for semantic guidance. | L | Planned | [Last.fm guidance acquisition plan](https://github.com/chrober/bliss-similarity-design/blob/main/LASTFM_GUIDANCE_ACQUISITION_PLAN.md), [product roadmap](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/BLISS_PLAYLIST_OPTIMIZER_IMPLEMENTATION_PLAN.md) |
| Local listening and library-signals provider | Replace the narrowly scoped play-count provider with one reusable, Bliss-first source for local play, recency, freshness, skip, and recent-affinity guidance. | XL | Proposed | [Local library guidance plan](https://github.com/chrober/bliss-similarity-design/blob/main/LOCAL_LIBRARY_GUIDANCE_PLAN.md) |
| Favor long-unheard or recently played tracks | Add a signed per-job last-played preference, allowing rediscovery of unheard tracks or intentional recent-listening momentum. | M | Proposed | [Local library guidance plan](https://github.com/chrober/bliss-similarity-design/blob/main/LOCAL_LIBRARY_GUIDANCE_PLAN.md) |
| Favor older or newer library additions | Add a signed per-job library-age preference using Lyrion's durable first-seen time rather than catalog scan time. | M | Proposed | [Local library guidance plan](https://github.com/chrober/bliss-similarity-design/blob/main/LOCAL_LIBRARY_GUIDANCE_PLAN.md) |
| Avoid skips and favor recent affinity | Use APC skip history as a one-way avoidance signal and positive DPSV as an optional recent-enjoyment boost. | L | Proposed | [Local library guidance plan](https://github.com/chrober/bliss-similarity-design/blob/main/LOCAL_LIBRARY_GUIDANCE_PLAN.md) |
| Player-specific history and ratings | Evaluate player affinity and explicit ratings only after a privacy, coverage, and source-policy design. | L | Deferred | [Local library guidance plan](https://github.com/chrober/bliss-similarity-design/blob/main/LOCAL_LIBRARY_GUIDANCE_PLAN.md) |
| Fill every source gap with N bridge tracks | Preserve source order and insert exactly the configured bridge count into every original transition, with global repeat and unique-membership validation. | XL | Planned | [Product roadmap](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/BLISS_PLAYLIST_OPTIMIZER_IMPLEMENTATION_PLAN.md), [UX status](docs/UX_STATUS.md) |
| Repeat-window spacer repair | Add only as many tracks as necessary to make an otherwise immutable source order satisfy artist and album spacing constraints. | XL | Planned | [Product roadmap](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/BLISS_PLAYLIST_OPTIMIZER_IMPLEMENTATION_PLAN.md), [UX status](docs/UX_STATUS.md) |
| Duration-based targets | Extend playlists to a chosen or doubled playback duration, with explicit duration tolerance and quality trade-offs. | L | Planned | [Product roadmap](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/BLISS_PLAYLIST_OPTIMIZER_IMPLEMENTATION_PLAN.md), [UX status](docs/UX_STATUS.md) |
| Playlist provenance and parameter restoration | Embed reproducible Better Call Bliss metadata in generated M3U files, then offer to restore those parameters when the playlist is reused as input. | M | Planned | [Product roadmap](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/BLISS_PLAYLIST_OPTIMIZER_IMPLEMENTATION_PLAN.md) |
| Durable preview history and reports | Retain job history across LMS restarts, make reports downloadable/searchable, and support explicit result disposal. | L | Planned | [UX status](docs/UX_STATUS.md), [product roadmap](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/BLISS_PLAYLIST_OPTIMIZER_IMPLEMENTATION_PLAN.md) |
| Persistence-phase cancellation and recovery | Let accepted-output work be cancelled safely and recover from interrupted playlist or queue publication. | XL | Planned | [UX status](docs/UX_STATUS.md) |
| Per-leg and provider/cache diagnostics | Add a drill-down of route legs plus a complete provider/cache diagnostic view without overloading normal preview results. | M | Partial | [UX status](docs/UX_STATUS.md), [guidance data flow](docs/GUIDANCE_DATA_FLOW.md) |
| Persistent quick-action progress in Material | Provide subtle ongoing progress for the three **Bliss me there...** actions instead of relying only on short-lived notifications. | L | Planned | [Product roadmap](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/BLISS_PLAYLIST_OPTIMIZER_IMPLEMENTATION_PLAN.md) |
| Alternative result-list or library-view UX | Explore a navigable LMS result surface, inspired by BlissMixer's **Create bliss mix**, alongside the rich Extras editor. | L | Planned | [Product roadmap](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/BLISS_PLAYLIST_OPTIMIZER_IMPLEMENTATION_PLAN.md) |
| Extended Isolation Forest routing | Make the currently visible but disabled BlissMixer strategy available to native playlist and route search. | XL | Planned | [UX status](docs/UX_STATUS.md) |
| Shared A-to-B path model for playlist gaps | Converge destination routing and multi-gap playlist filling on the shared inner path engine, including global budget allocation and placement. | XL | Partial | [Acoustic path-finding design](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/ACOUSTIC_PATH_FINDING_DESIGN.md) |
| Depth-aware discovery and trajectory-aware path quality | Improve candidate discovery beyond frozen endpoint shortlists and evaluate a complete route's progress rather than only local pairwise legs. | XL | Planned research | [Acoustic path-finding design](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/ACOUSTIC_PATH_FINDING_DESIGN.md), [destination-route investigation](https://github.com/chrober/bliss-similarity-design/blob/feature/playlist-optimization/DESTINATION_ROUTE_QUALITY_INVESTIGATION.md) |
| Richer transition evidence and listener evaluation | Test directional/boundary-aware acoustic evidence and listener-reviewed quality before treating whole-track similarity as transition truth. | XL | Planned research | [Transition-quality experiment plan](https://github.com/chrober/bliss-similarity-design/blob/main/BLISS_TRANSITION_QUALITY_EXPERIMENT_PLAN.md), [mixing roadmap](https://github.com/chrober/bliss-similarity-design/blob/main/docs/evaluation/mixing-roadmap.md) |
| ListenBrainz guidance provider | Add an optional, failure-tolerant semantic source through the reusable guidance-provider architecture. | L | Planned | [UX status](docs/UX_STATUS.md), [guidance data flow](docs/GUIDANCE_DATA_FLOW.md) |
| Reuse guidance providers from `bliss-mixer` | Let `bliss-mixer` host the same Bliss-first guidance SPI while ranking its existing candidate pool. | XL | Follow-up | [Guidance data flow](docs/GUIDANCE_DATA_FLOW.md) |

## Maintenance rule

Add an item only when there is a concrete source document to link. Keep this
file concise: move explanatory detail, designs, experiments, and acceptance
criteria into the linked document rather than expanding the table. Historical
implementation checkpoints and `docs/superpowers` plans are supporting context,
not independent backlog rows.  
