# Verbal

Verbal is an iOS app that turns spoken job descriptions into clear, priced
quotes for tradespeople. The repository includes the app, widget extension,
Supabase backend, automated tests, and public site content.

## Repository map

| Path | Purpose |
| --- | --- |
| `Verbal/` | Main iOS app target. Xcode synchronizes this directory automatically. |
| `Configuration/` | Project-level app build configuration and the development StoreKit catalog. Kept outside the synchronized app target so Xcode does not copy configuration files as resources. |
| `Verbal/Models/` | Domain models and value types. |
| `Verbal/Services/` | Application, persistence, device, and integration services. |
| `Verbal/Supabase/` | iOS Supabase client setup and authentication adapters. |
| `Verbal/Theme/` | App-wide typography and visual foundations. |
| `Verbal/Views/` | SwiftUI screens grouped by product feature; `Components/` is shared UI. |
| `VerbalWidgets/` | Widget extension target. |
| `VerbalTests/`, `VerbalUITests/` | Unit and UI test targets. |
| `supabase/` | Database migrations, Edge Functions, backend tests, and auth templates. |
| `docs/` | Public legal pages, release material, and development runbooks. |
| `evals/` | Quote-extraction evaluation runner and stable fixtures. |
| `scripts/` | Repeatable repository maintenance and verification scripts. |

## Conventions

- Keep each product feature together under `Verbal/Views/<Feature>/`. Put a
  reusable view in `Views/Components/` only after it is used across features.
- Add models to `Models/`; add side-effecting or integration code to
  `Services/` or `Supabase/` according to its responsibility.
- Keep app-target configuration under `Configuration/` and target-local
  configuration inside the relevant target directory. Do not place app
  configuration under `Verbal/`, which is a synchronized source target.
- Treat `supabase/migrations/` as append-only. Use descriptive, timestamped
  migrations and keep Edge Function-specific helpers next to their function.
- Do not commit generated build products, local Supabase state, package
  installs, or Xcode user data; `.gitignore` covers these.

## Getting started

Open `Verbal.xcodeproj` in Xcode, select the **Verbal** scheme, and run it on
an iOS simulator or device. The scheme uses
`Configuration/Verbal.storekit` for local subscription testing.

Backend deployment notes are in [`supabase/README.md`](supabase/README.md).
RevenueCat setup notes are in
[`docs/development/revenuecat.md`](docs/development/revenuecat.md).
