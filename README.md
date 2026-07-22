# Bliss 'Em All

Bliss 'Em All is a Lyrion Music Server plugin for auditable playlist
optimization powered by Bliss. It will depend on a compatible BlissMixer
installation for `bliss.db` and captured scoring settings, plus the platform's
`bliss-playlist-optimizer` executable. The current bundled optimizer requires
the learned matrix captured by the compatible BlissMixer fork.

The current development milestone is installable on ARM64 LMS systems. It
exposes the complete planned UX shell while connecting one safe writable slice:
saved-playlist selection, **Optimize order > Reorder only**, per-job Adaptive
and repeat settings initialized from BlissMixer defaults, background native
preview, result review, and explicit creation of a new optimized copy. Every
future-only item is visibly marked **Not connected yet** and cannot start a job. See
[`docs/UX_STATUS.md`](docs/UX_STATUS.md) for the feature matrix.

## Try the live preview

After installing the `BlissEmAll` directory and restarting LMS, open
**Extras > Bliss 'Em All**. Select a saved playlist, adjust its per-job Adaptive
parameters and repeat windows, choose **Create optimized copy**, enter its new
name, and select **Run read-only preview**. Use a zero artist or album look-back to disable that
constraint for a single-artist or single-album collection. The result area
shows the selected strategy, objective, worst transition, and numbered proposed
order. Preview is read-only. Only the separate **Create optimized copy** action
on a completed result writes anything.

Requests, native output, and stderr are kept beneath the LMS cache in
`blissemall/jobs`. Creation uses Lyrion's core M3U formatter, publishes a new
file atomically, creates the LMS playlist object, and verifies both catalog and
file order before reporting success. Existing names are rejected and the
source playlist is never changed.

The plugin owns LMS menus, preferences, background jobs, optional semantic
providers, reports, and atomic playlist persistence. The native optimizer will
remain network-free.

Licensed under GPL-3.0-only. See `LICENSE`.
