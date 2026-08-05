# EUROCENTRIC

**EUROCENTRIC — A Journey Through Nine Thousand Years** is a static, map-led historical journey.
Its twenty-four chapters move from the first farmers to the present through one continuous
illuminated route and four families of optional map interactions.

The site is built with Astro, TypeScript and PixiJS. Public prose and interface copy are English.

## Current product direction

The website is the active product and the sole starting point for a new Mac exploration. The earlier
iPhone project under `native/` is frozen and preserved as historical work. Its product, design,
architecture and production decisions do not govern the Mac project. No Mac technology, interface or
product model has been selected.

## Live site

[bstandal.github.io/europa-long-journey](https://bstandal.github.io/europa-long-journey/)

## Development

```sh
cd site
npm install
npm run dev
```

`npm run build` validates the story, citations and asset metadata before generating the static
site. GitHub Pages deployment is configured in `.github/workflows/deploy.yml`.

## Administration

- [Chapter notifications](site/docs/admin/newsletter.md)
