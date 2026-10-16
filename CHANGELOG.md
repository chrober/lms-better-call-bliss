# Changelog

## Unreleased

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

