import { defineConfig } from "astro/config";

const [owner, repository] = (process.env.GITHUB_REPOSITORY || "").split("/");
const base =
  process.env.BASE_PATH ||
  (process.env.GITHUB_ACTIONS === "true" && repository ? `/${repository}` : "/");
const site =
  process.env.SITE_URL ||
  (owner ? `https://${owner}.github.io` : "https://example.github.io");

export default defineConfig({
  site,
  base,
  output: "static",
  trailingSlash: "always",
  vite: {
    server: {
      host: "0.0.0.0",
      allowedHosts: ["terminal.local"],
    },
    build: {
      target: "es2022",
    },
  },
});
