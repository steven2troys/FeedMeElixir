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
- **Households** - Households, memberships (admin/member roles), email invitations, automation tier settings
- **Pantry** - Inventory items with quantities (Decimal), categories, multi-location storage, expiration dates, nutrition (embedded), transaction audit log. Broadcasts via PubSub
- **Shopping** - Shopping lists (main + custom), per-member sharing, real-time item sync via PubSub. Checked items trigger AI pantry sync
- **Recipes** - Recipes with ingredients linked to pantry items, photos, cooking logs. "Cooked It" atomically decrements pantry quantities via Ecto transactions
- **AI** - OpenRouter API client with streaming, 14 tool/function calls, encrypted BYOK API keys (Cloak.Ecto), conversation persistence + sharing, ephemeral chat (drawer)
- **Budgets** - Budget tracking per household, AI authority levels (recommend/purchase), procurement budget checks
- **Profiles** - User dietary preferences, allergies, favorites, dislikes, nutrition display tier preference
- **MealPlanning** - Meal plans with date ranges, recipe items with servings multiplier, shopping needs calculation (deducts pantry stock), AI weekly suggestions. Broadcasts via PubSub
- **Procurement** - Plans from meal plans/restock/expiring items, supplier linking with deep links, budget checks, status workflow (suggested → approved → shopping → fulfilled). Broadcasts via PubSub
- **Suppliers** - Global default suppliers (Instacart, Amazon Fresh, Walmart, Kroger, Target) + custom suppliers, per-household enabling with default selection, deep link search URL generation
- **Nutrition** - Embedded `Nutrition.Info` schema (JSONB on pantry items + recipe ingredients), AI batch estimation, recipe totals/per-serving calculation, display tiers (none/basic/detailed), backfill for existing items
- **Scheduler** - Oban cron dispatcher that fans out per-household jobs based on automation tier and schedule settings

### Key Patterns

- **All schemas use binary (UUID) primary keys**
- **Scope-based auth**: Always use `@current_scope` (never `@current_user`). Pass `current_scope` as first arg to context functions. Access user via `@current_scope.user` in templates
- **PubSub real-time**: Contexts use `subscribe(household_id)` and `broadcast/3` for real-time updates across devices. Topics: `pantry:`, `shopping:`, `shopping_list:`, `procurement:`, `meal_planning:`
- **GenServer batch processing**: `FeedMe.Pantry.Sync` debounces checked shopping items, then fires a single AI call to update pantry (10min prod, 30s dev, disabled in test)
- **LiveView streams**: Used for all collections to prevent memory issues. Streams are NOT enumerable - must refetch and re-stream with `reset: true` to filter
- **Colocated JS hooks**: Use `:type={Phoenix.LiveView.ColocatedHook}` with `.` prefix names (e.g., `.PhoneNumber`)
- **Oban background jobs**: 3 queues (default/10, procurement/5, meal_planning/5). `FeedMe.Scheduler` is a cron dispatcher that fans out per-household jobs to `WeeklySuggestion`, `DailyPantryCheck`, `ProcurementReminder` workers. Workers check `automation_tier` before acting
- **Automation tiers**: Household setting (off/recommend/cart_fill/auto_purchase) controls how much AI acts autonomously. Schedule settings: `weekly_suggestion_enabled`, `weekly_suggestion_day`, `daily_pantry_check_enabled`
- **Embedded Nutrition.Info**: JSONB schema on `Pantry.Item` and `Recipes.Ingredient` with calories, macros, micronutrients, serving_size, source. Display filtered by tier preference
- **Chat drawer**: Ephemeral AI chat via `ChatDrawerHooks` (attach_hook pattern). Messages live in socket assigns only, no DB persistence. Uses `Task.Supervisor` for async AI calls

### Integration Flows

These are the major cross-context data pipelines:

1. **Meal Plan → Procurement → Shopping → Pantry**: `MealPlanning.calculate_shopping_needs/1` aggregates ingredients, deducts pantry stock → `Procurement.create_from_meal_plan/2` creates plan with supplier deep links → `Procurement.sync_to_shopping_list/2` adds items to main list → checked items trigger `Pantry.Sync`
2. **Shopping → Pantry Sync**: `Pantry.Sync` GenServer queues checked items, debounces, spawns Task via `SyncTaskSupervisor` → AI loop matches items to pantry (fuzzy), converts units, creates/updates items with nutrition
3. **Recipe "Cooked It"**: `Recipes.cook_recipe/3` atomically decrements all linked pantry items (quantity × servings multiplier), creates `CookingLog`, triggers restock notifications
4. **Procurement from Restock/Expiring**: `Procurement.create_from_restock/2` and `create_from_expiring/2` create plans from `Pantry.items_needing_restock/1` and `items_expiring_soon/2`
5. **Nutrition Pipeline**: AI batch estimation → `Nutrition.Info` embedded schema on items/ingredients → `Nutrition.recipe_total/1` sums across ingredients → `recipe_per_serving/1` divides by servings → `for_display/2` filters by user's tier preference
6. **AI Chat**: Persistent (`AI.chat/4` with DB messages + streaming) and ephemeral (`AI.ephemeral_chat/2` for drawer). Both support 14 tools via `AI.Tools` with context `%{household_id:, user:}`
7. **Cron Scheduling**: `Scheduler` dispatches daily at 8/9/10am UTC → fans out to per-household workers based on `automation_tier` and schedule settings
8. **Supplier Deep Links**: `Suppliers.generate_deep_link/2` replaces `{query}` in supplier's URL template with encoded product name → stored on `ProcurementItem.deep_link_url`

### Web Layer (lib/feed_me_web/)

- `live/` - LiveView pages
- `components/` - Reusable UI components (core_components.ex has `<.icon>`, `<.input>`, etc.), chat_drawer.ex (FAB + sliding panel), nutrition_component.ex
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
