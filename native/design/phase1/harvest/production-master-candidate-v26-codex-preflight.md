# Harvest candidate v26 — Codex preflight

Status: `CODEX_PROVISIONAL_NON_SHIPPING_REVIEW`

Candidate:
`production-master-candidate-v26-garments-local-composite.png`
(`e00eebcac9c20b7cd4c30193ea21bc7f032981817840cb85694298240d0618ca`)

The v25 full-frame review missed a material F5 defect. The seated man's
button placket and several knitted, factory-cut T-shirt silhouettes read as
modern clothing. This correction does not reopen the composition or grant a
production-master decision.

## Passed provisional checks

- The canvas remains exactly `1290 × 2796` without upscaling.
- The modern button placket, ribbed neck cues and smooth knitted-shirt surfaces
  have been replaced locally with coarse, irregular, undyed woven wraps and
  tunics.
- Faces, hair, working hands, feet, tools, hearth, grain, storage, architecture,
  fields, animals, weather, camera and light remain on the pixel-bound parent
  outside the authored garment-and-shoulder masks.
- The image retains the v23 clay hearth vessel and v25 cereal correction.
- Decoded raw-frame hashes are identical to v25 across the complete frame above
  the edited people region, below it and along the untouched left edge.
- The local joins show no visible rectangular crop edge at one-to-one
  inspection. The complete-image comparison against v25 is PSNR `35.609663 dB`
  and SSIM `0.978717`.

## Permanent visual regression rule

An Early Neolithic garment fails the F5 gate if it retains any modern knitted
T-shirt surface, ribbed crew neck, polo or button placket, set-in factory
sleeve, machine-finished hem, tailored trouser construction or contemporary
dress silhouette. A plain colour does not make a modern cut historical.

## Gates still open

- Candidate v26 is a flattened local-correction input. It has no clean plates,
  parallax disocclusion, production layers, masks, state variants or Reduce
  Motion plates.
- Hair, shoulders, cloth edges and hand occlusion require inspection again in
  the eventual separated people layer.
- The three destinations still lack empty, receiving and committed visual
  states, so causal legibility cannot yet be judged in motion.
- Simulator motion, integrated sound, VoiceOver parity and hard-kill restore
  remain scene-level gates. Physical display and interruption checks remain in
  the consolidated device gate.

