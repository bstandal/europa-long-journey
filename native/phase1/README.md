# Phase 1 experience laboratory

Status: `LEGACY_2_5D_LAB_SUSPENDED_2026_07_30`

The authored real-time 3D medium lock supersedes this laboratory's visual
production route. Its interaction, reducer, accessibility and restoration
evidence may be reused, but its frame, layer, mask and compositor plan cannot
be extended into shipping scenes. See
[`../blueprint/real-time-3d-medium-lock-2026-07-30.md`](../blueprint/real-time-3d-medium-lock-2026-07-30.md).

[experience-lab.json](./experience-lab.json) fixes five
laboratory scenes from the three free chapters, one for each native interaction
grammar. The set is an implementation boundary, not a shipping content package.

The first visual lock is `The Harvest Had to Last`. The editor-in-chief selected
option 1 on 23 July 2026. Its [selection record](../design/phase1/harvest/selection.json)
binds the exact bytes of the [selected image](../design/phase1/harvest/selected-direction.png)
and its required production corrections.

The current implementation includes a
[non-shipping Harvest SceneSpec fixture](./fixtures/harvest-option-1.scene.json),
its [production brief](../design/phase1/harvest/scene-production-brief.md), the
[fixture gate](./validate-harvest-fixture.mjs) and a deterministic
[SceneFramePlanner](../ios/Sources/SceneRuntime/SceneFramePlanner.swift). A typed
[visual-state resolver](../ios/Sources/SceneRuntime/SceneInteractionVisualState.swift)
binds the exact `Allocate` reducer state to the authored variants and rebuilds
the same frame plan from the saved visual snapshot. The fixture reserves future
asset paths and a non-shipping visual binding; it does not supply production
layers, audio, a Metal-rendered composition, an editor-approved destination
split or a playable scene.

The editor-in-chief approved the rebuilt
[Harvest composition and anatomy](../design/phase1/harvest/reconstruction-master-draft-v2.png)
on 23 July 2026. The exact image bytes and the limited approval scope are now
enforced by the [approval gate](./validate-reconstruction-approval.mjs). The
image remains below production resolution, unlayered and excluded from the
zero-approved native asset registry. A separate
[rain-logic pass](../design/phase1/harvest/rain-logic-pass-v2.png) corrects the
dry foreground reading without changing what the approval authorizes; it is
also non-shipping and unapproved as an asset.

The current contract keeps touch geometry valid over the complete interpolated
camera rail, attaches transferred grain to the rendered source, transfer and
destination transforms, and preserves foreground occlusion in Reduce Motion.
Shipping packages may use the implemented `Allocate` visual adapter only;
scenes using the other four grammars remain laboratory-only until their native
runtime adapters exist.

The non-shipping [Harvest editor-review draft](./editor-review/harvest/README.md)
replaces a hidden exact distribution with three minimum obligations and three
genuinely allocable surplus shares. A DEBUG-only Swift laboratory prototype
tests that proposal without changing the approved public `Allocate` contract
or entering a release build. The draft remains `DRAFT_AWAITING_EDITOR_APPROVAL`
and `PROHIBITED` for shipping.

The laboratory must prove these transitions before the complete Chapter 01
vertical slice begins:

| Grammar | Historical action | Permanent result |
|---|---|---|
| `allocate` | Divide one visible harvest between winter food, reserve and spring seed | The seasonal store becomes a durable order between present consumption and the next field |
| `assemble` | Join posts, hearth and storage into a working house | A rebuilt frame, worn threshold and remembered plot outlive one structure |
| `transform` | Open the same ground to new hearths, fields and herd lanes | Daughter settlements remain cut into the growing farming landscape |
| `pressure` | Hold the northern valleys through terrain, stores and inhabited refuge | A Christian corridor remains open towards León and the Duero |
| `trace` | Put an ocean route on schedule through steam, coal, watches and ports | The route establishes a global schedule later systems inherit |

Existing web controls are not implementation targets. `KEEP` preserves the
historical mechanism; `REWRITE` replaces the existing behaviour completely.
No laboratory fixture can enter a production package or native asset registry
without its own editor approval, provenance record and package gate.
