# Bliss 'Em All

Bliss 'Em All is a Lyrion Music Server plugin for auditable playlist
optimization powered by Bliss. It will depend on a compatible BlissMixer
installation for `bliss.db` and captured scoring settings, plus the platform's
`bliss-playlist-optimizer` executable. The current bundled optimizer requires
the learned matrix captured by the compatible BlissMixer fork.

The current development milestone is installable on ARM64 LMS systems. It
exposes the complete planned UX shell while connecting one safe vertical slice:
saved-playlist selection, **Optimize order > Reorder only**, per-job Adaptive
and repeat settings initialized from BlissMixer defaults, background native
preview, and result review. Every future-only item
is visibly marked **Not connected yet** and cannot start a job. See
[`docs/UX_STATUS.md`](docs/UX_STATUS.md) for the feature matrix.

## Try the live preview

After installing the `BlissEmAll` directory and restarting LMS, open
**Extras > Bliss 'Em All**. Select a saved playlist, adjust its per-job Adaptive
parameters and repeat windows, choose the future output disposition, and select
**Run read-only preview**. Use a zero artist or album look-back to disable that
constraint for a single-artist or single-album collection. The result area
shows the selected strategy, objective, worst transition, and numbered proposed
order.

The action is read-only. Requests, native output, and stderr are kept beneath
the LMS cache in `blissemall/jobs`; no playlist file is written.

The plugin owns LMS menus, preferences, background jobs, optional semantic
providers, reports, and atomic playlist persistence. The native optimizer will
remain network-free.

Licensed under GPL-3.0-only. See `LICENSE`.
