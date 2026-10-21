# Changelog

## Unreleased

- Make **Add spacing tracks as needed** use the optimizer's global
  minimum-total repeat-window repair instead of treating a calculated minimum
  size as an exact fixed-source extension target.
- Allow every frozen source gap to receive a different number of additions,
  add none at the beginning or end, and preserve the existing maximum-additions
  control as a hard global ceiling.
- Validate native per-gap counts, source subsequence, unique membership,
  candidate identities per physical gap, endpoint exclusion, and final artist,
  album, and track repeat proofs before a repaired preview can be accepted.
- Use a positional preflight for preserved source order so local repeat
  conflicts are not mistaken for an already feasible playlist; optimized
  source order is frozen before the native repair determines its real minimum.

## 0.22.8

- Add **Fill every gap with N bridge tracks** as a preserved-order playlist
  workflow with an exact per-gap count.
- Plan all source gaps together so repeat windows, unique membership, and
  candidate reuse constraints apply to the complete generated playlist.
- Report live per-gap search progress and fail before expensive artifact or
  candidate preparation when fixed spacing cannot satisfy source-track repeat
  constraints.
- Bundle optimizer 0.2.5.

## 0.22.7

- Bundle optimizer 0.2.4 so destination routes enforce artist, album, and
  track repeat windows at their locked destination anchors.
- Fail fast when the configured `Bliss me there...` bridge budget cannot
  satisfy the repeat windows, instead of accepting an invalid direct route.

## 0.22.6

- Show a player-targeted Material error notification when an automatic
  `Bliss me there...` route fails before changing the queue.
- Return immediate preview-start feedback from Extras and keep its elapsed
  timer responsive while server-side preparation continues.
- Move cold candidate-inventory rebuilds out of Lyrion's main event loop,
  report their preparation phases, and run native background work at reduced
  CPU and I/O priority.
- Avoid repeated native-process polling and expensive re-hashing or playlist
  object inflation during preview preparation.

## 0.22.5

- Cover persistence of provider-declared enum overrides such as the Last.fm
  acquisition source on the host settings page.

## 0.22.4

- Add configurable MusicBrainz-aware artist repeat identities. The default
  blocks any shared credited artist, while primary-artist and exact Bliss
  credit modes remain available per job.
- Publish Lyrion contributor and MusicBrainz artist identities to the native
  optimizer so repeat windows use the selected policy during candidate
  admission and routing.
- Clarify the repeat-identity choices in settings, Extras, completed-preview
  diagnostics, and the algorithm guide.

- Relay validated structured diagnostics from native guidance providers back
  to the provider plugin that owns their Lyrion log category.
- Track direct Last.fm provider preparation through native optimizer
  diagnostics instead of fabricating an artifact-backed semantic provider
  state, preserving accurate fresh, degraded, and failed reporting.
- Support the optimizer's provider-facing candidate metadata flow so direct
  Last.fm scoring can match bounded candidates by title, artist, album,
  recording MBID, and artist MBIDs without changing Bliss eligibility.
- Update the strategy guide, guidance data flow, implementation history, and
  improvement backlog for the operational LastMix and API Key acquisition
  paths.

