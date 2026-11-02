# Automatic playlist improvement

Status: approved; not yet implemented.  
Owner: Better Call Bliss and bliss-playlist-optimizer.  

## Goal

Replace the separate spacing and difficult-transition choices with one automatic
playlist-improvement workflow. Offer two independent goals: satisfy repeat
windows by adding spacing tracks, and smooth difficult transitions by adding
useful bridges. Either goal or both can be selected; require at least one.

## Approaches

- Keep both existing workflow choices: the implementation remains simpler, but
  users must understand and select different internal mechanisms.
- Combine the two goals in one workflow, planning required spacing first and
  then optional improvements with the remaining shared budget: this preserves
  both intentions without making users choose an internal algorithm. This is
  the selected approach.
- Replace both with a new joint optimizer: potentially better global trade-offs,
  but materially larger and less predictable than the requested integration.

## Behavior and constraints

- Respect Preserve or Optimize source order; retain every original track once
  and keep all hard repeat and eligibility rules. Never write output during a
  preview.
- Use one maximum-additions budget across both phases. When enabled, spacing
  has priority and searches for the smallest feasible number of additions. If
  that cannot be achieved within the budget or candidate constraints, report
  the failure rather than silently weakening a rule.
- When smoothing is enabled, consider the actual adjacent transitions after
  spacing, including transitions involving spacing tracks. Add only useful,
  repeat-safe bridges using the remaining budget; zero optional additions is a
  valid result. A previously occupied source gap must not be silently skipped.
- Smoothing alone keeps the current hard repeat-window requirements and
  explains conflicts that require spacing. Spacing alone does not add optional
  bridges. If no spacing is needed, do not fail: proceed to smoothing or return
  the unchanged valid route, as appropriate.
- Identify the reason for each addition and report phase-specific counts and
  useful progress. Preserve established log formats unless a new line is needed.
- Keep acoustic selection Bliss-first and existing guidance advisory. Reuse
  existing path and candidate-discovery machinery; avoid a second independent
  implementation of scoring or repeat validation.
- Maintain compatibility with old saved options and reject unsupported native
  capabilities clearly. Update native request/result schemas, capability
  negotiation, host result validation, UI and product documentation together.

## Verification

Test both goals separately and together, no-conflict sources, impossible and
insufficient-budget cases, preserved and optimized source ordering, seeded
determinism, duplicate/artist/album constraints, smoothing across added tracks,
and final-route validation. Check progress, diagnostics, old option mapping,
and read-only previews. Exercise the host and optimizer test suites; live Pi
deployment and testing require separate authorization.
