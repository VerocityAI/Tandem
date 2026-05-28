#!/usr/bin/env tsx
/**
 * apply-branding.ts
 *
 * Single source of truth: packages/branding/branding.config.json.
 *
 * Reads the branding config and writes generated files into:
 *   - apps/mobile/lib/core/branding/branding.g.dart
 *   - apps/marketing/src/site.config.ts
 *   - functions/src/branding.ts
 *
 * Also patches:
 *   - apps/mobile/android/app/build.gradle.kts  (applicationId)
 *   - apps/mobile/ios/Runner.xcodeproj/project.pbxproj  (PRODUCT_BUNDLE_IDENTIFIER)
 *
 * Run via `npm run branding` from the repo root. Idempotent. Safe to run in CI.
 *
 * Renaming the product is a single PR: edit branding.config.json, run this script,
 * commit the regenerated files.
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..");

interface BrandingConfig {
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
  colors: {
    accentLight: string;
    accentLightHover?: string;
    accentDark: string;
    accentDarkHover?: string;
    bgLight: string;
    bgDark: string;
  };
  social?: { twitter?: string; linkedin?: string };
}

const cfgPath = join(repoRoot, "packages", "branding", "branding.config.json");
const cfg: BrandingConfig = JSON.parse(readFileSync(cfgPath, "utf8"));

const HEADER_LINES = [
  "GENERATED FILE — do not edit by hand.",
  "Source: packages/branding/branding.config.json",
  "Regenerate via: npm run branding",
];

function ensureDir(path: string) {
  const dir = dirname(path);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function writeIfChanged(path: string, content: string) {
  ensureDir(path);
  const existing = existsSync(path) ? readFileSync(path, "utf8") : "";
  if (existing === content) {
    console.log(`  unchanged  ${path}`);
    return;
  }
  writeFileSync(path, content, "utf8");
  console.log(`  wrote      ${path}`);
}

// ---------- Dart (Flutter) ----------
function writeDart() {
  const out = join(repoRoot, "apps", "mobile", "lib", "core", "branding", "branding.g.dart");
  const header = HEADER_LINES.map((l) => `// ${l}`).join("\n");
  const content = `${header}
// ignore_for_file: type=lint

import 'package:flutter/material.dart';

class Branding {
  Branding._();

  static const String name = ${JSON.stringify(cfg.name)};
  static const String shortName = ${JSON.stringify(cfg.shortName)};
  static const String tagline = ${JSON.stringify(cfg.tagline)};
  static const String description = ${JSON.stringify(cfg.description ?? "")};
  static const String domain = ${JSON.stringify(cfg.domain)};
  static const String marketingUrl = ${JSON.stringify(cfg.marketingUrl ?? "")};
  static const String appUrl = ${JSON.stringify(cfg.appUrl ?? "")};
  static const String supportEmail = ${JSON.stringify(cfg.supportEmail ?? "")};

  // Colors (sourced from prototype Clawpilot palette).
  static const Color accentLight = Color(0xFF${cfg.colors.accentLight.slice(1).toUpperCase()});
  static const Color accentLightHover = Color(0xFF${(cfg.colors.accentLightHover ?? cfg.colors.accentLight).slice(1).toUpperCase()});
  static const Color accentDark = Color(0xFF${cfg.colors.accentDark.slice(1).toUpperCase()});
  static const Color accentDarkHover = Color(0xFF${(cfg.colors.accentDarkHover ?? cfg.colors.accentDark).slice(1).toUpperCase()});
  static const Color bgLight = Color(0xFF${cfg.colors.bgLight.slice(1).toUpperCase()});
  static const Color bgDark = Color(0xFF${cfg.colors.bgDark.slice(1).toUpperCase()});
}
`;
  writeIfChanged(out, content);
}

// ---------- Astro (marketing) ----------
function writeAstro() {
  const out = join(repoRoot, "apps", "marketing", "src", "site.config.ts");
  const header = HEADER_LINES.map((l) => `// ${l}`).join("\n");
  const content = `${header}

export const site = ${JSON.stringify(cfg, null, 2)} as const;

export type SiteConfig = typeof site;
`;
  writeIfChanged(out, content);
}

// ---------- Functions ----------
function writeFunctions() {
  const out = join(repoRoot, "functions", "src", "branding.ts");
  const header = HEADER_LINES.map((l) => `// ${l}`).join("\n");
  const content = `${header}

export const branding = ${JSON.stringify(cfg, null, 2)} as const;

export type Branding = typeof branding;
`;
  writeIfChanged(out, content);
}

// ---------- Android applicationId patch ----------
function patchAndroid() {
  const gradlePath = join(repoRoot, "apps", "mobile", "android", "app", "build.gradle.kts");
  if (!existsSync(gradlePath)) {
    console.log(`  skip       ${gradlePath} (run \`flutter create\` first)`);
    return;
  }
  let content = readFileSync(gradlePath, "utf8");
  const re = /applicationId\s*=\s*"[^"]*"/;
  if (!re.test(content)) {
    console.warn(`  warning    no applicationId in ${gradlePath}`);
    return;
  }
  const next = content.replace(re, `applicationId = "${cfg.androidApplicationId}"`);
  if (next !== content) writeIfChanged(gradlePath, next);
  else console.log(`  unchanged  ${gradlePath}`);
}

// ---------- iOS bundle id patch ----------
function patchIos() {
  const pbx = join(repoRoot, "apps", "mobile", "ios", "Runner.xcodeproj", "project.pbxproj");
  if (!existsSync(pbx)) {
    console.log(`  skip       ${pbx} (run \`flutter create\` first)`);
    return;
  }
  let content = readFileSync(pbx, "utf8");
  const re = /PRODUCT_BUNDLE_IDENTIFIER\s*=\s*[^;]+;/g;
  const next = content.replace(re, `PRODUCT_BUNDLE_IDENTIFIER = ${cfg.iosBundleId};`);
  if (next !== content) writeIfChanged(pbx, next);
  else console.log(`  unchanged  ${pbx}`);
}

console.log(`apply-branding: ${cfg.name} (${cfg.bundleIdPrefix})`);
writeDart();
writeAstro();
writeFunctions();
patchAndroid();
patchIos();
console.log("done.");
