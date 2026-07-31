# Chapter 01 directed animation/contact candidate

This directory contains the project-authored work-motion library for the six
approved Chapter 01 interactions. It is a bounded production candidate, not a
new gameplay system and not final character-contact art.

The library supplies 20 reusable human clips covering line tension, two-hand
vessel transfer, sowing, grain allocation, wet-store lift and repair, Iron
Gates pole/line/steering work, longhouse raising and repair, herd guidance,
field staking and the final loaded barrier. Each clip has authored contact
windows and a safe incomplete frame. No clip contains dialogue, lip-sync,
motion capture, free cloth/hair simulation or autonomous crowd behaviour.

## Authority

`directed-animation-spec.json` is the source-text authority for timing, poses
and contact windows. `integration-contract.json` binds the clips to the six
locked interaction IDs, grammars and `WorldEffect` IDs without duplicating or
replacing reducer logic.

The integration rule is strict:

1. The Chapter 01 reducer selects stable material state and owns completion.
2. Stable state plus deterministic tick selects and samples a clip.
3. Contact windows drive only deterministic scene IK against authored sockets.
4. Animation, collision and physics cannot advance a beat or emit a
   `WorldEffect`.
5. Release returns to `human.work.safe-release` or another reducer-selected
   safe incomplete pose.
6. Restoration reconstructs clip phase from saved deterministic state and
   never repeats already-journalled haptics.

## Outputs

- `generated/chapter01-directed-animation-library.usdc` — canonical UsdSkel
  library with profile-specific adult A, adult B and youth bindings for every
  role-eligible clip. Each profile keeps its own rest and bind transforms. A
  one-millimetre skinned witness triangle makes each resource discoverable by
  RealityKit; the integrator disables that technical child before playback.
- `generated/chapter01-directed-animation-library.usdz` — deterministic,
  RealityKit-compatible package.
- `generated/chapter01-directed-animation-library.blend` — inspectable Blender
  action library; it is a review artifact rather than runtime authority.
- `generated/validation-report.json` — contract, skeleton, timing, contact and
  policy validation.
- `build-manifest.json` and `generated/SHA256SUMS` — hashes, toolchain and open
  gates.

## Build

The build is pinned to Blender 5.2.0 LTS. It verifies every source lock,
compiles twice, compares canonical outputs byte-for-byte, runs Apple's USD
checker in strict ARKit mode on both USDC and USDZ, and loads the package
offline through RealityKit to require all 51 role-eligible profile resources.

```sh
native/production/3d/chapter01/animation-library/scripts/build.sh
```

The hero rig contributes only its rights-cleared joint order, rest transforms
and bind transforms. All movement and contact data in this directory is
project-authored. See `provenance.json`.

## Open production gates

`finalContactGate` remains `OPEN`. World-space target sockets, per-cell IK,
hand/foot/prop penetration review, final deformation and physical-iPhone
camera/contact checks must pass after integration. This candidate must not be
described as final animation art before those gates close.
