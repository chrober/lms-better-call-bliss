# Extras defaults implementation plan

> **For agentic workers:** Use superpowers:executing-plans. Implement with failing behavior tests before each change.

**Goal:** Let Extras previews choose current plugin defaults or an independently saved reusable configuration.

**Architecture:** Store a versioned, validated Extras profile separately from general preferences. Apply it only to Extras editor and preview requests; preserve the existing destination-route path. Capture provider policy and BlissMixer scoring weights with the preview, while resolving live capabilities and trusted resources at execution.

**Tech Stack:** Perl, Lyrion preferences and web templates, JavaScript, Test::More.

**Spec:** `docs/superpowers/specs/2026-10-29-extras-defaults-design.md`

## Global constraints

Preserve destination-route defaults, captured job options, explicit acceptance, trusted provider resources, and established logs. Keep zero and false values. Do not persist source, player, destination, output name, seed, credentials, paths, or matrix data.

## Review focus

Test missing or changed providers, disabled and unavailable providers, zero/false values, temporary matrix unavailability, and changes to inherited static weights after saving. Verify job restoration and destination actions remain independent.

### Task 1: Profile data and validation

**Files:** Create `BetterCallBliss/ExtrasDefaults.pm` and `tests/extras_defaults.t`; modify `BetterCallBliss/Defaults.pm` as needed.

- [ ] Write failing tests for initial plugin defaults, field whitelist, atomic validation, explicit false/zero, and schema/version and provider changes.
- [ ] Implement a versioned profile with validated save and resolution against current plugin capabilities, preserving unavailable provider entries and saved learned blend.
- [ ] Run the focused tests and relevant existing job-option tests.

### Task 2: Editor persistence and selection

**Files:** Modify `BetterCallBliss/Web.pm` and `BetterCallBliss/HTML/EN/plugins/BetterCallBliss/index.html`; extend relevant tests and `strings.txt`.

- [ ] Write failing tests for selecting, saving, loading, current job restoration, hidden values, and source/player exclusion.
- [ ] Add explicit save/load controls and status, using the profile only on new Extras editors and explicit loads; warn before replacing changed values.
- [ ] Verify classic and Material-compatible form behavior and focused tests.

### Task 3: Frozen preview scoring and provider policy

**Files:** Modify `BetterCallBliss/JobOptions.pm`, `BetterCallBliss/RequestBuilder.pm`, and related tests.

- [ ] Write failing tests for captured static weights, provider enabled state, descriptor validation, matrix absence, and unchanged destination-route behavior.
- [ ] Carry validated profile values into the preview request and captured job, without accepting untrusted provider paths or changing shared route defaults.
- [ ] Run focused request, provider, route, and job tests.

### Task 4: Documentation and verification

**Files:** Modify `BetterCallBliss/README.md` and `docs/UX_STATUS.md`.

- [ ] Document defaults selection and save/load semantics and their limits.
- [ ] Run available Perl and Python regression suites and `git diff --check`; report environment limitations precisely.
- [ ] Review the complete diff against the spec and commit the completed feature on its dedicated branch.
