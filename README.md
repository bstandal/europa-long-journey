# EUROPA

**EUROPA — A Journey Through Nine Thousand Years** is a static, map-led historical journey.
Its twenty-four chapters move from the first farmers to the present through one continuous
illuminated route and four families of optional map interactions.

The site is built with Astro, TypeScript and PixiJS. Public prose and interface copy are English.

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

- [Usage analytics](site/docs/admin/analytics.md)
- [Chapter notifications](site/docs/admin/newsletter.md)
