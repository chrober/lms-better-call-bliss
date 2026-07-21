# Bliss 'Em All

Bliss 'Em All is a Lyrion Music Server plugin for auditable playlist
optimization powered by Bliss. It will depend on a compatible BlissMixer
installation for `bliss.db` and captured scoring settings, plus the platform's
`bliss-playlist-optimizer` executable. The current bundled optimizer requires
the learned matrix captured by the compatible BlissMixer fork.

The current development milestone is installable on ARM64 LMS systems. It
exposes the complete planned UX shell while connecting one safe vertical slice:
saved-playlist selection, **Optimize order > Reorder only**, inherited Adaptive
settings, background native preview, and result review. Every future-only item
is visibly marked **Not connected yet** and cannot start a job. See
[`docs/UX_STATUS.md`](docs/UX_STATUS.md) for the feature matrix.

## Try the live preview

After installing the `BlissEmAll` directory and restarting LMS, open
**Applications / My Apps > Bliss 'Em All**. Check **System status**, choose
**Optimize a saved playlist**, select **Optimize order**, then **Reorder only**,
review the inherited BlissMixer settings, and select **Run preview**. Completed jobs appear under
**Recent results**, including the selected strategy, objective, worst
transition, repeat-window validation, and numbered proposed order.

The action is read-only. Requests, native output, and stderr are kept beneath
the LMS cache in `blissemall/jobs`; no playlist file is written.

The plugin owns LMS menus, preferences, background jobs, optional semantic
providers, reports, and atomic playlist persistence. The native optimizer will
remain network-free.

Licensed under GPL-3.0-only. See `LICENSE`.
