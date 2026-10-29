# Extras defaults design

## Intent

Let Extras previews use either current defaults from the contributing plugins or an independently saved Extras configuration. Bliss me there continues to use the general Better Call Bliss and other plugin defaults, including its existing route-specific options.

## Approaches

- Separate, complete Extras defaults selected on the Extras page: predictable and editable in context; plugin changes do not silently alter the saved configuration. This is the selected approach.
- Per-setting overrides inheriting general defaults: fewer duplicated values, but more source labels and less predictable changes when other plugins are adjusted.
- Independent settings-page profiles: flexible, but duplicates the Extras editor and adds navigation and profile management.

## User experience

On Extras, offer **Use plugin defaults** and **Use saved Extras defaults**, with **Save current settings as Extras defaults** and **Load selected defaults**. Saving persists reusable options and selects the saved set for future new previews; it does not start a preview or write a playlist. Loading replaces current reusable editor values; warn before discarding edits. Until an Extras set exists, make the saved option unavailable and explain why. Show save success or a validation error. Switching the selected default source is persistent; loading it into an existing editor is explicit.

Running a preview uses the values in the editor without changing defaults. Opening a new editor uses the chosen source; result, polling, failure and rerun views restore the job's captured values rather than reapplying defaults. Keep inactive control values for later mode changes. No source playlist, player, destination, job identity, output name, or generation seed becomes a default.

Capture reusable preview controls, including algorithm, repeat windows and identity mode, search and addition options, scoring and learned blend, and enabled provider policies with explicit zero and false values. The four BlissMixer static scoring weights are not currently editable on Extras; capture their effective values as part of the saved scoring configuration and make their source clear. Do not snapshot the learned matrix itself, credentials, provider executable paths, library data, or capabilities. A temporarily missing matrix must not erase the saved desired learned blend, even if the run uses zero.

Provider controls remain descriptor driven. Capture the enabled state and declared job policy values, not provider-wide setup such as credentials or acquisition settings. Validate stored and submitted values against current descriptors; handle absent, unavailable, added, or changed providers visibly and safely without losing unrelated saved values. New settings with no saved value use the current plugin default and identify their source. Never enable an unavailable provider or weaken Bliss eligibility and repeat constraints.

## Boundaries and compatibility

Apply Extras defaults only when initializing or explicitly loading the Extras editor, not in the shared global job-default function or destination-route actions. Preserve existing normalized job snapshots, read-only preview and explicit acceptance, queue-anchor checks, localization, classic web and Material Skin behavior, and existing log contracts. Upgrades initially select plugin defaults, preserving current behavior. Version the saved data and whitelist reusable fields; revalidate at save and use. Errors must not partially replace the saved configuration.

## Verification

Cover independent selection and persistence, migration, save/load and invalid values, zero/false and inactive controls, provider enablement and descriptor changes, static weights, unavailable learned matrix, job restoration, and unchanged Bliss me there requests. Exercise the Extras UI and provider controls in classic and Material where available; run the relevant existing job, guidance and destination tests. Update owned user documentation after implementation.
