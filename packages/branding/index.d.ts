export interface BrandingColors {
  accentLight: string;
  accentLightHover?: string;
  accentDark: string;
  accentDarkHover?: string;
  bgLight: string;
  bgDark: string;
}

export interface BrandingSocial {
  twitter?: string;
  linkedin?: string;
}

export interface BrandingConfig {
  name: string;
  shortName: string;
  tagline: string;
  description?: string;
  domain: string;
  marketingUrl?: string;
  appUrl?: string;
  supportEmail?: string;
  bundleIdPrefix: string;
  androidApplicationId: string;
  iosBundleId: string;
  colors: BrandingColors;
  social?: BrandingSocial;
}

declare const config: BrandingConfig;
export default config;
