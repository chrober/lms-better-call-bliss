# Bliss 'Em All

Bliss 'Em All is a Lyrion Music Server plugin for auditable playlist
optimization powered by Bliss. It will depend on a compatible BlissMixer
installation for `bliss.db` and captured scoring settings, plus the platform's
`bliss-playlist-optimizer` executable. A learned matrix improves Adaptive
scoring when present but is optional.

The current development milestone is installable on ARM64 LMS systems and
implements a read-only vertical slice: Applications/My Apps registration, live
capability status, saved-playlist selection, inherited Adaptive settings,
background native reorder preview, and proposed-order review. It deliberately
does not create or modify playlists yet.

## Try the live preview

After installing the `BlissEmAll` directory and restarting LMS, open
**Applications / My Apps > Bliss 'Em All**. Check **System status**, choose
**Optimize a saved playlist**, select **Reorder only**, review the inherited
BlissMixer settings, and select **Run preview**. Completed jobs appear under
**Recent results**, including the selected strategy, objective, worst
transition, repeat-window validation, and numbered proposed order.

The action is read-only. Requests, native output, and stderr are kept beneath
the LMS cache in `blissemall/jobs`; no playlist file is written.

The plugin owns LMS menus, preferences, background jobs, optional semantic
providers, reports, and atomic playlist persistence. The native optimizer will
remain network-free.

Licensed under GPL-3.0-only. See `LICENSE`.
