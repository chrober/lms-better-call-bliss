# Changelog

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

