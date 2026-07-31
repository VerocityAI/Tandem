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
        "accent-dark-hover": site.colors.accentDarkHover,
        bg: site.colors.bgLight,
        "bg-dark": site.colors.bgDark,
        "gradient-start": site.colors.gradientStart,
        "gradient-mid": site.colors.gradientMid,
        "gradient-end": site.colors.gradientEnd,
        success: site.colors.success,
        warning: site.colors.warning,
        danger: site.colors.danger,
        card: site.colors.cardLight,
        "card-dark": site.colors.cardDark,
        surface: site.colors.surfaceLight,
        "surface-dark": site.colors.surfaceDark,
      },
      fontFamily: {
        sans: ['"Segoe UI"', "Aptos", "Calibri", "-apple-system", "BlinkMacSystemFont", "sans-serif"],
      },
    },
  },
  darkMode: "media",
} satisfies Config;
