import type { Config } from "tailwindcss";
import { site } from "./src/site.config";

export default {
  content: ["./src/**/*.{astro,html,js,jsx,md,mdx,ts,tsx}"],
  theme: {
    extend: {
      colors: {
        accent: site.colors.accentLight,
        "accent-hover": site.colors.accentLightHover ?? site.colors.accentLight,
        "accent-dark": site.colors.accentDark,
        bg: site.colors.bgLight,
        "bg-dark": site.colors.bgDark,
      },
      fontFamily: {
        sans: ['"Segoe UI"', "Aptos", "Calibri", "-apple-system", "BlinkMacSystemFont", "sans-serif"],
      },
    },
  },
  darkMode: "media",
} satisfies Config;
