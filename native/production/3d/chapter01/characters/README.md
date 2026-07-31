# Chapter 01 hero-character candidate

This directory holds a rights-cleared shared rig candidate for Chapter 01. The
runtime USD contains three individually cloneable local-origin roots:
`hero_adult_a`, `hero_adult_b` and `hero_youth`. Preview staging is present only
in the inspectable Blender file and review PNG.

The build is intentionally classified `HERO_RIG_CANDIDATE` with
`finalArtGate: OPEN`. It replaces the former barrel-shaped tunic and trouser
tubes with a fitted woven bodice, bounded short sleeves, a fixed-drape
knee-length skirt and a separate waist cinch. The upper surface is a
project-authored selection and rest-space offset of the same pinned CC0 human
base; the skirt, waist gathering, hem flare and small fixed folds are
deterministic project geometry derived from rig measurements. Pinned CC0 hair
receives a small project-authored rest-space clearance to prevent hairline and
braid clipping.
No free cloth, hair or collision simulation is used.

The output remains a restrained visual reconstruction rather than a claim for
one exact early-Neolithic garment cut. It does not claim final face, hand, eye,
hair, deformation, historical-costume or world-contact quality. The 9:16
review render and normalized before/after evidence are recorded in
[`VISUAL_REVIEW.md`](./VISUAL_REVIEW.md).

Run `../tooling/build-hero-characters.sh` after exporting these pinned source
locations:

```sh
export CHAPTER01_MPFB_REPOSITORY=/absolute/path/to/mpfb2
export CHAPTER01_MAKEHUMAN_ASSETS_ROOT=/absolute/path/to/makehuman-assets
export CHAPTER01_SKIN_TEXTURES_ROOT=/absolute/path/to/resolved-skin-textures
../tooling/build-hero-characters.sh
```

The wrapper validates every source hash, produces USDC and USDZ, runs the
ARKit USD checker, checks root/local-origin and preview exclusion, then compares
two builds byte-for-byte. It also rejects any runtime or package reference to
the removed garment source. `rightsGate` is `PASS`; final-art, close-contact,
historical-costume and world-cell integration gates remain open.
