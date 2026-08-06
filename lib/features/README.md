# Feature boundaries

Each feature owns three layers:

- `presentation`: screens and widgets; delegates work to the application layer.
- `application`: use cases, controllers, state, and repository contracts.
- `data`: Supabase-backed repository implementations and feature DTO mapping.

Cross-feature primitives belong in `lib/data` only when they are genuinely
shared. Business-data access must always carry a `company_id`, while PostgreSQL
RLS remains the final tenant authorization boundary. AI provider calls must go
through Supabase Edge Functions; provider secrets never belong in Flutter.
