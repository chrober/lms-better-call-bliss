# Candidate Library Selection and Cache Implementation Plan

**Goal:** Preserve the invoking virtual library for Bliss me there and reuse candidate inventories and shared identity snapshots on demand.  
**Architecture:** Accept library context supplied by the invoking UI; never infer a browser-local selection that the server did not receive. Store separate validated inventory manifests per complete cache identity and reuse the independently validated shared track identity snapshot.  
**Tech stack:** Lyrion Perl, SQLite, JSON artifacts and existing LMS stubs.  

## Constraints

- Do not prebuild libraries, change Material Skin, restart Lyrion, or mutate a queue during tests.
- Preserve explicit All tracks, player fallback, source/anchor handling, candidate restrictions and existing log formats.
- Cache reuse must reject changed Bliss database, LMS scan, roots, virtual-library membership and malformed or missing artifacts.
- Concurrent jobs must not see partially published snapshots or the wrong library's inventory.

## Tasks

- [ ] Trace Material, Lyrion menu and route-command library context end to end; add tests for explicit candidate and generic library IDs, player fallback, All tracks and invalid IDs. If the UI sends no browser selection, do not claim it can be inferred server-side.
- [ ] Add tests and per-key atomic manifests, preserving legacy cache compatibility and repeatable A/B/A and restart reuse.
- [ ] Separate and test the library-independent snapshot lifecycle, binding it to database, scan and media-root identities, and reuse it on subsequent on-demand library builds.
- [ ] Test membership changes, hash/path failures, shared-snapshot invalidation, overlapping requests, existing previews and regression suite; update owned documentation to reflect verified behavior.
