# FeedMe

AI-powered household management app for grocery shopping, pantry inventory, meal planning, and procurement. Built with Elixir/Phoenix LiveView for real-time multi-device sync and conversational AI with tool calling.

## Feature Highlights

- **Pantry Inventory** - Multi-location storage, quantity tracking (Decimal precision), expiration alerts, auto-restock thresholds, barcode scanning, transaction audit log
- **Shopping Lists** - Main + custom lists, per-member sharing, real-time sync via PubSub, category sorting, AI-powered pantry sync on checkout
- **Recipes** - Ingredients linked to pantry items, photo carousel, "Cooked It" atomic inventory decrement, cooking logs with ratings, nutrition per-serving
- **Meal Planning** - Weekly plans with recipe scheduling, shopping needs calculation (deducts pantry stock), AI weekly suggestions
- **Procurement** - Agentic pipeline from meal plans/restock/expiring items to supplier-linked shopping lists with deep links and budget checks
- **AI Chat** - BYOK model selection via OpenRouter, 14 tool calls (add items, search recipes, suggest meals, create procurement plans), persistent conversations + ephemeral drawer, voice and vision input
- **Nutrition Tracking** - AI batch estimation, embedded data on items and ingredients, recipe totals/per-serving, configurable display tiers
- **Suppliers** - Instacart, Amazon Fresh, Walmart, Kroger, Target with deep link search URLs, custom supplier support
- **Budgeting** - Weekly/monthly limits, AI authority levels (recommend/purchase), procurement budget checks
- **Taste Profiles** - Per-member dietary restrictions, allergies, favorites, dislikes used as AI context
- **Background Automation** - Oban cron jobs for weekly meal suggestions, daily pantry checks, procurement reminders with per-household automation tiers

## Tech Stack

- **Backend**: Elixir 1.15+, Phoenix 1.8, PostgreSQL
- **Frontend**: Phoenix LiveView 1.1, Tailwind CSS v4
- **AI**: OpenRouter API (Claude, GPT-4, Gemini), streaming + tool calling
- **Background Jobs**: Oban with cron scheduling
- **Auth**: Google OAuth 2.0 (Ueberauth)
- **Encryption**: Cloak.Ecto for API key storage
- **HTTP Client**: Req

## Prerequisites

- Elixir 1.15+ / Erlang OTP 26+
- PostgreSQL 14+
- Google OAuth credentials (client ID + secret)
- OpenRouter API key (or users provide their own via BYOK)

## Getting Started

1. Copy `.env.example` to `.env` and fill in the required values:

   ```
   SECRET_KEY_BASE, DATABASE_URL, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,
   OPENROUTER_API_KEY, ENCRYPTION_KEY
   ```

2. Install dependencies and set up the database:

   ```bash
   mix setup
   ```

3. Start the dev server:

   ```bash
   mix phx.server
   ```

   Or with an IEx console: `iex -S mix phx.server`

4. Visit [`localhost:4000`](http://localhost:4000)

## Running Tests

```bash
mix test                      # Run all tests (auto-creates/migrates test DB)
mix test test/path/file.exs   # Run a single test file
mix test --failed             # Re-run only previously failed tests
mix precommit                 # Full pre-commit check: compile (warnings-as-errors) + format + test
```

## Project Structure

All data is scoped to households via a multi-tenant model with UUID primary keys.

**Context modules** (`lib/feed_me/`): Accounts, Households, Pantry, Shopping, Recipes, AI, Budgets, Profiles, MealPlanning, Procurement, Suppliers, Nutrition, Scheduler

**Web layer** (`lib/feed_me_web/`): LiveView pages, reusable components, auth controllers, router with `live_session` scoping

See [CLAUDE.md](CLAUDE.md) for development conventions and [ARCHITECTURE.md](ARCHITECTURE.md) for deep technical reference.

## Development Routes

- `/dev/dashboard` - Phoenix LiveDashboard (dev only)
- `/dev/mailbox` - Swoosh email preview (dev only)
