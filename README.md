# i Book

i Book is an AI Business Operating System for SMEs, built as a multi-company
Flutter + Supabase SaaS platform.

## Current implementation phase

Phase 1 establishes the authentication and tenant boundary:

- user profiles linked to `auth.users`
- companies and branches
- roles and permissions
- company memberships and branch assignments
- company settings
- automatic owner/company initialization
- explicit Data API grants and Row Level Security
- composite tenant foreign keys for cross-company integrity

The CRM, sales, purchasing, inventory, finance, HR, projects, AI, storage, and
subscription modules remain intentionally pending until the tenant foundation
passes local and live security tests.

## Flutter application

The Flutter client uses feature-based clean architecture with Riverpod for
dependency injection/application state, GoRouter for mobile/web navigation, and
repository-backed Supabase access.

### Required environment variables

- `SUPABASE_URL`: the project URL from Supabase project settings.
- `SUPABASE_PUBLISHABLE_KEY`: the preferred client-side key for new projects.
- `SUPABASE_ANON_KEY`: supported as a legacy alternative when the project still
  uses an anonymous JWT key. Provide either this or the publishable key, not both.
- `APP_ENV`: optional environment name; defaults to `development`.

### Run the app

Pass public configuration at compile time:

```powershell
flutter run `
  --dart-define=APP_ENV=development `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

If the public values are omitted, the app opens a safe configuration screen
instead of attempting to initialize Supabase.

## Secrets

Only the Supabase project URL and a client-safe publishable/anonymous key may be
provided to Flutter. The client key is not a replacement for Row Level Security.
Never place a `service_role`, legacy service-role JWT, or `sb_secret` key in the
repository or frontend application.

The service-role credential previously stored in the external project notes must
be rotated before deployment.

## Database workflow

```powershell
supabase start
supabase db reset
supabase test db
supabase db push --dry-run
```

Do not push migrations to the hosted project until the local reset and security
checks pass.
