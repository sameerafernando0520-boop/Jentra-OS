# Jentra OS

Jentra OS is a Windows-first, multi-tenant operating platform for growing Sri
Lankan businesses. This repository is a deliberate greenfield implementation;
legacy application code and visual assets are not part of the product.

## Workspace

- `apps/jentra_desktop` — Flutter desktop application.
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
flutter run -d windows --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

The app can launch without backend configuration in design preview mode. Any
authoritative business command remains unavailable until a live development
backend is configured and confirms the operation.
