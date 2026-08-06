# Jentra OS

The engineering contract for this repository lives in **[AGENTS.md](AGENTS.md)**.
Read it before writing any code — it defines the architecture, the tenancy and
secret-handling invariants, the database rules, and the required validation
commands.

Supporting documents:

- `docs/DEVELOPMENT_ROADMAP.md` — module order, per-module acceptance criteria
  and testing checklists
- `docs/DELIVERY_PLAN.md` — current position, phase gates, and the next
  concrete actions

Quick reminders, all expanded in `AGENTS.md`:

- Product name is **Jentra OS**; `i Book` and `i Connect` are dead names, but
  database objects and migration filenames are never renamed for branding.
- Every business record is scoped by `company_id`, and RLS is the real
  authorization boundary.
- Flutter gets only the Supabase URL and a publishable key via `--dart-define`.
  No `service_role` or `sb_secret_*` key ever reaches the client.
- Money and stock are computed server-side in transactional PostgreSQL
  functions, never in Dart.
- No business logic in widgets; follow the
  `application` / `domain` / `data` / `presentation` layering.
- `flutter analyze` and `flutter test` must both be clean before reporting a
  task done.
