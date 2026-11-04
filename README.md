# Jentra OS

Jentra OS is a Windows-first, multi-tenant operating platform for growing Sri
Lankan businesses. This repository is a deliberate greenfield implementation;
legacy application code and visual assets are not part of the product.

## Workspace

- `apps/jentra_desktop` — Flutter desktop application.
- `apps/jentra_sales` — adaptive Sales companion for Android, tablets and desktop browsers; initial preview, live portfolio rollout pending.
- `packages/jentra_design_system` — semantic tokens and enterprise UI kit.
- `packages/jentra_domain` — framework-free contracts and business primitives.
- `packages/jentra_platform` — Supabase, local storage, connectivity, and OS adapters.
- `docs/blueprint` — approved product, architecture, security, UX, and delivery dossier.
- `supabase` — versioned database migrations, Edge Functions, and pgTAP tests.

## Development configuration

Copy `.env.example` values into secure launch configuration or pass them as
`--dart-define` values. No privileged Supabase secret belongs in the client.

```powershell
flutter pub get
cd apps/jentra_desktop
flutter run -d windows --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

The app can launch without backend configuration in design preview mode. Any
authoritative business command remains unavailable until a live development
backend is configured and confirms the operation.

## Company setup and operation

Use the [company setup and operating guide](docs/user-guide/README.md) for the
real company pilot, daily workflows, analytics and reviewed AI. The accompanying
[feature inventory](docs/user-guide/feature-inventory.csv) checks all advertised
desktop navigation routes against source. The [capability review](docs/user-guide/feature-completeness.md)
identifies remaining functional gaps, including group/staff administration and
the separate salesman mobile app. Production configuration, backend
installation, independent acceptance and the current cleanup scope are tracked in
the [launch readiness record](docs/development/launch-readiness-20261028.md).
