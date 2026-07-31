# Chapter 01 hero candidate — visual review

Status: `HERO_RIG_CANDIDATE`

Final-art gate: `OPEN`

Shipping status: `BLOCKED`

## Evidence

- Original candidate: `review/chapter01-hero-character-preview-before-9x16.png`
- Revised candidate: `outputs/chapter01-hero-character-preview.png`
- Combined comparison: `review/chapter01-hero-character-preview-comparison.png`
- Normalized viewport: 720 × 1280 pixels, portrait 9:16
- State: identical three-character working-pose lineup, camera, lighting and
  stage. The original Blender source was re-rendered at the revised viewport;
  this is not a comparison against the old 3:4 crop.

The comparison reads left-to-right: original, revised.

## Result

The revision is a material improvement and remains below final-art quality.

Resolved in the static review state:

- The separate torso and trouser tubes no longer define the silhouette.
- The knee-length skirt, waist cinch and shaped upper garment create one
  coherent tunic silhouette.
- Shoulders and upper arms are covered by one continuous skinned surface;
  the former floating shoulder shell and exposed shoulder gap are gone.
- The former thigh, crotch and trouser-shell intersections are absent.
- All three figures now fit the 9:16 review frame closely enough to compare
  adult and youth proportions.
- Pinned hair geometry has deterministic rest-space clearance instead of a
  runtime hair collision or simulation.

Final-art blockers still visible:

- The fitted upper cloth follows anatomy too literally, especially around the
  adult-b chest. It needs an authored low-frequency drape pass that preserves
  clearance while suppressing body-surface contours.
- Neckline and waist boundaries remain irregular. They need production-ready
  seam/binding geometry and deformation review in the final working clips.
- Faces, eyes, hands and hair remain candidate-level and do not meet the
  close-camera character bar.
- One static lineup cannot prove sleeve, hair, hem or hand/object contact
  through the directed animation library. Those contact gates remain open.
- The belted woven tunic is a restrained reconstruction. Exact costume cut and
  period-specific finishing remain subject to the final historical-art gate.

## Classification

`HERO_RIG_CANDIDATE` is retained. Rights, deterministic build and offline USD
validation pass. The visual evidence does not support closing `finalArtGate`.
