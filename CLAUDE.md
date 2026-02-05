# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
mix setup                     # Full project setup (deps, DB, assets)
mix phx.server                # Start dev server at localhost:4000
iex -S mix phx.server         # Start with IEx console
mix test                      # Run all tests (auto-creates/migrates DB)
mix test test/path/file.exs   # Run a single test file
mix test --failed             # Re-run only failed tests
mix precommit                 # Run before committing: compile (warnings-as-errors) + deps.unlock --unused + format + test
mix format                    # Format code
mix ecto.gen.migration name   # Generate a new migration
mix ecto.migrate              # Run pending migrations
mix ecto.reset                # Drop + create + migrate + seed
```

The `precommit` alias runs in the `:test` environment (configured in `cli/0`).

## Architecture

FeedMe is an AI-powered household management app (Phoenix 1.8, LiveView 1.1, PostgreSQL). All data is scoped to households via a multi-tenant model.

### Context Modules (lib/feed_me/)

Each domain area is a context module with a public API:

- **Accounts** - Google OAuth authentication, user management. Uses scope-based auth (`@current_scope`, NOT `@current_user`)
- **Households** - Households, memberships (admin/member roles), email invitations
- **Pantry** - Inventory items with quantities (Decimal), categories, expiration dates, transaction audit log. Broadcasts changes via PubSub
- **Shopping** - Shopping lists (main + custom), real-time item sync via PubSub/Channels. Checked items trigger AI pantry sync
- **Recipes** - Recipes with ingredients linked to pantry items. "Cooked It" atomically decrements pantry quantities via Ecto transactions
- **AI** - OpenRouter API client with streaming, tool/function calling, encrypted BYOK API keys (Cloak.Ecto), conversation persistence
- **Budgets** - Budget tracking per household
- **Profiles** - User dietary preferences, allergies, favorites, dislikes

### Key Patterns

- **All schemas use binary (UUID) primary keys**
- **Scope-based auth**: Always use `@current_scope` (never `@current_user`). Pass `current_scope` as first arg to context functions. Access user via `@current_scope.user` in templates
- **PubSub real-time**: Contexts use `subscribe(household_id)` and `broadcast/3` for real-time updates across devices
- **GenServer batch processing**: `FeedMe.Pantry.Sync` debounces checked shopping items, then fires a single AI call to update pantry (10min prod, 30s dev, disabled in test)
- **LiveView streams**: Used for all collections to prevent memory issues. Streams are NOT enumerable - must refetch and re-stream with `reset: true` to filter
- **Colocated JS hooks**: Use `:type={Phoenix.LiveView.ColocatedHook}` with `.` prefix names (e.g., `.PhoneNumber`)

### Web Layer (lib/feed_me_web/)

- `live/` - LiveView pages
- `components/` - Reusable UI components (core_components.ex has `<.icon>`, `<.input>`, etc.)
- `controllers/` - Traditional controllers (auth callbacks)
- `router.ex` - Routes with `live_session` scoping for auth

### Important Rules from AGENTS.md

- Use `Req` for HTTP (not HTTPoison/Tesla)
- Tailwind v4: no config file, uses `@import "tailwindcss"` syntax in app.css
- Never use `<.flash_group>` outside layouts.ex
- Never write inline `<script>` tags; use colocated hooks or external hooks in `assets/js/`
- Never nest multiple modules in the same file
- Never use map access syntax on structs (use `my_struct.field`)
- Forms must use `to_form/2` assigned in LiveView, accessed via `@form[:field]` in templates

### Environment Variables

Required (see `.env.example`): `SECRET_KEY_BASE`, `DATABASE_URL`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `OPENROUTER_API_KEY`, `ENCRYPTION_KEY`

Dev/test loads from `.env` via dotenvy.
