import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import tailwind from "@astrojs/tailwind";
import { site } from "./src/site.config";

export default defineConfig({
  site: site.marketingUrl ?? `https://${site.domain}`,
  integrations: [tailwind({ applyBaseStyles: false }), sitemap()],
  output: "static",
  build: { format: "directory" },
});
