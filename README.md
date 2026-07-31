# Cohyve

> **Working name** — the product name is centralized in
> [`packages/branding/branding.config.json`](packages/branding/branding.config.json)
> and can be changed across the entire monorepo with a single `npm run branding`.

Cohyve is a multi-platform creator collaboration tool. Users sign in with
Google, paste any **YouTube / Instagram / TikTok** channel URL or handle, and
get an AI-analysed profile plus a ranked list of compatible collaborators —
each match comes with an explainable fit-score breakdown and an AI rationale.

## Monorepo layout

```
apps/
  marketing/        Astro 4 + Tailwind — public marketing site (cohyve.app)
  mobile/           Flutter app — iOS, Android, Web (app.cohyve.app)
functions/          Firebase Cloud Functions (gen2, TypeScript, Node 20)
packages/
  branding/         Single source of truth for product name/colours/domains
  shared-types/     Zod schemas + TypeScript types shared by server & marketing
tools/              Codegen scripts (apply-branding.ts, …)
docs/               Design notes and the original HTML prototype
```

## Prerequisites

- **Node.js 20** + npm 10
- **Flutter SDK 3.22+** (with `dart` on PATH)
- **Firebase CLI** (`npm i -g firebase-tools`)
- **FlutterFire CLI** (`dart pub global activate flutterfire_cli`)
- **Java 17** (Android builds)
- A Firebase project for each environment (`cohyve-dev`, `cohyve-staging`,
  `cohyve-prod`) with two Hosting sites per project:
  `cohyve-<env>-marketing` and `cohyve-<env>-app`.

## One-time setup

```powershell
# 1. Install workspace dependencies (runs branding codegen via postinstall)
npm install

# 2. Bootstrap Flutter native folders + Firebase options
cd apps/mobile
flutter create . --platforms=ios,android,web --org app.cohyve --project-name cohyve
flutterfire configure --project cohyve-dev --out lib/core/firebase/firebase_options.dart
flutter pub get
dart run build_runner build --delete-conflicting-outputs
cd ../..

# 3. Configure Firebase
firebase login
firebase use dev

# 4. Set required secrets (Secret Manager — never commit these)
firebase functions:secrets:set YOUTUBE_API_KEY
firebase functions:secrets:set GEMINI_API_KEY
```

## Local development

```powershell
# Terminal 1 — Firebase emulators (auth, firestore, functions, storage, hosting)
firebase emulators:start

# Terminal 2 — marketing site (http://localhost:4321)
npm --workspace apps/marketing run dev

# Terminal 3 — Flutter app pointing at emulators
cd apps/mobile
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

## Rename the product

Cohyve is the working name. To rename:

1. Edit [`packages/branding/branding.config.json`](packages/branding/branding.config.json)
   (`name`, `domain`, `bundleIdPrefix`, `colors`, …).
2. Run `npm run branding`. Codegen rewrites:
   - `apps/marketing/src/site.config.ts`
   - `apps/mobile/lib/core/branding/branding.g.dart`
   - `functions/src/branding.ts`
   - Android `applicationId` and iOS `PRODUCT_BUNDLE_IDENTIFIER`
3. Commit the regenerated files.

## Deploy

```powershell
# Marketing site (Astro → Hosting target "marketing")
npm run deploy:marketing

# Flutter web app (→ Hosting target "app")
npm run deploy:app

# Backend (Functions + Firestore rules + indexes + Storage rules)
npm run deploy:backend
```

For CI-driven deploys see [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)
(manual dispatch, choose target × environment).

## Status

Phase 1 scaffolding — see [`docs/prototype.html`](docs/prototype.html) for the
original interactive prototype that informs the matching UX and copy.
