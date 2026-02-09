# Architecture Reference

FeedMe is a multi-tenant Elixir/Phoenix application with 13 context modules, real-time PubSub, an agentic AI pipeline, and Oban background job processing. This document covers the system architecture for developers extending the project.

## Multi-Tenant Model

All data is scoped to households. Every query filters by `household_id`. Authentication uses scope-based auth (`@current_scope`) rather than `@current_user`. Users access households via Membership records with admin/member roles.

```
User --has_many--> Membership --belongs_to--> Household
                   (role: admin | member)
```

Invitations use email-based tokens. Pending invitations are checked on OAuth login to auto-associate users with households.

## Context Modules

### Accounts (`lib/feed_me/accounts.ex`)
User management and Google OAuth. Schemas: User, UserToken. No PubSub.

### Households (`lib/feed_me/households.ex`)
Household CRUD, membership management, email invitations. Schemas: Household, Membership, Invitation. Household holds `automation_tier` (off/recommend/cart_fill/auto_purchase) and schedule settings (`weekly_suggestion_enabled`, `weekly_suggestion_day`, `daily_pantry_check_enabled`). No PubSub.

### Pantry (`lib/feed_me/pantry.ex`)
Multi-location inventory with quantity tracking (Decimal precision), categories (location-scoped), expiration dates, nutrition (embedded), and transaction audit log. Schemas: Item, Category, StorageLocation, Transaction. PubSub topic: `"pantry:#{household_id}"`.

### Shopping (`lib/feed_me/shopping.ex`)
Main + custom shopping lists with per-member sharing, category ordering, and auto-add-to-pantry-location. Schemas: List, Item, ListShare, CategoryOrder. PubSub topics: `"shopping:#{household_id}"`, `"shopping_list:#{list_id}"`.

### Recipes (`lib/feed_me/recipes.ex`)
Recipes with ingredients (linked to pantry items), photos (carousel with primary), cooking logs with ratings. "Cooked It" atomically decrements pantry. Schemas: Recipe, Ingredient, Photo, CookingLog. No PubSub.

### AI (`lib/feed_me/ai.ex`)
OpenRouter API client with streaming SSE and 14 tool calls. BYOK API keys encrypted via Cloak.Ecto. Persistent conversations with sharing, and ephemeral chat for the drawer. Schemas: ApiKey, Conversation, ConversationShare, Message. No PubSub.

### Budgets (`lib/feed_me/budgets.ex`)
Budget tracking with AI authority levels. `ai_can_auto_add?` and `ai_can_auto_purchase?` gate automation. `within_budget?` checks procurement totals. Schemas: Budget, Transaction. No PubSub.

### Profiles (`lib/feed_me/profiles.ex`)
Per-member taste profiles with dietary restrictions, allergies, favorites, dislikes, and nutrition display tier. `get_household_dietary_summary` aggregates all member profiles for AI context. Schemas: TasteProfile. No PubSub.

### MealPlanning (`lib/feed_me/meal_planning.ex`)
Weekly meal plans with recipe items, shopping needs calculation, and AI suggestions. `calculate_shopping_needs` aggregates ingredients across recipes, deducts pantry stock. Schemas: MealPlan, MealPlanItem. PubSub topic: `"meal_planning:#{household_id}"`.

### Procurement (`lib/feed_me/procurement.ex`)
Agentic pipeline from meal plans/restock/expiring items to supplier-linked shopping lists. Status workflow with budget checks. Schemas: ProcurementPlan, ProcurementItem. PubSub topic: `"procurement:#{household_id}"`.

### Suppliers (`lib/feed_me/suppliers.ex`)
Global defaults (Instacart, Amazon Fresh, Walmart, Kroger, Target) + custom suppliers. Per-household enabling with default selection. Deep link URL generation via search templates. Schemas: Supplier, HouseholdSupplier. No PubSub.

### Nutrition (`lib/feed_me/nutrition.ex`)
Embedded `Nutrition.Info` schema (JSONB) for pantry items and recipe ingredients. AI batch estimation (20 items per call), recipe totals/per-serving, display tier filtering. No schemas (uses embedded schema on other modules). No PubSub.

### Scheduler (`lib/feed_me/scheduler.ex`)
Oban cron dispatcher that fans out per-household jobs. Queries eligible households by automation_tier and schedule settings, enqueues WeeklySuggestion, DailyPantryCheck, or ProcurementReminder workers.

## Data Flow Pipelines

### Meal Plan → Procurement → Shopping → Pantry

The full agentic flow from meal planning through to inventory:

```
MealPlanning.calculate_shopping_needs(meal_plan)
  → Aggregates ingredient quantities × servings_multiplier
  → Groups by (name, unit), sums quantities
  → Deducts current pantry stock
  → Returns items where need > 0

Procurement.create_from_meal_plan(meal_plan, user)
  → Creates ProcurementPlan (status: :suggested, source: :meal_plan)
  → For each need: creates ProcurementItem with supplier deep link

Procurement.sync_to_shopping_list(plan, user)
  → Filters items with status :needed
  → Creates Shopping.Items on main list
  → Updates procurement items to :in_cart with shopping_item_id

Shopping item checked → Pantry.Sync (see below)
```

### Shopping → Pantry Sync

GenServer-based debounced AI sync from checked shopping items to pantry:

```
Shopping.toggle_item_checked
  → Pantry.Sync.queue_item(household_id, location_id, item)
     → GenServer deduplicates by shopping_item_id
     → Starts/resets debounce timer (10min prod, 30s dev)

Timer fires:
  → Spawns Task via FeedMe.Pantry.SyncTaskSupervisor
  → AI loop (max 3 rounds):
     1. Sends checked items + current pantry state to OpenRouter
     2. AI fuzzy-matches items to existing pantry (case-insensitive)
     3. AI calls update_pantry_item or create_pantry_item tools
     4. Results passed back for next iteration
  → Items updated/created with nutrition data
```

### AI Chat Pipeline

Two modes with shared tool infrastructure:

```
Persistent (AI.chat/4):
  → Save user message to DB
  → Build history (exclude tool messages for cross-provider compat)
  → Call OpenRouter with system prompt + history + tool definitions
  → Tool call loop: execute tool → save messages → re-call for summary
  → Streaming: accumulates chunks via Agent, callback on each chunk

Ephemeral (AI.ephemeral_chat/2):
  → No DB persistence (socket assigns only)
  → Context-aware system prompt based on page_context
  → Same tool calling loop as persistent
  → Used by ChatDrawerHooks
```

### Nutrition Pipeline

```
AI estimation (batch or individual)
  → Nutrition.Info embedded schema saved on Item/Ingredient
  → Nutrition.recipe_total(recipe) sums across all ingredients
  → Nutrition.recipe_per_serving(recipe) divides by servings
  → Nutrition.for_display(info, tier) filters by user preference
```

## Background Jobs

### Oban Configuration

| Queue | Workers | Purpose |
|-------|---------|---------|
| `:default` | 10 | Scheduler dispatcher |
| `:procurement` | 5 | DailyPantryCheck, ProcurementReminder |
| `:meal_planning` | 5 | WeeklySuggestion |

### Cron Schedule

| Time (UTC) | Job Type | Description |
|------------|----------|-------------|
| 8:00 AM | `weekly_suggestion` | Fans out WeeklySuggestion to households with matching day |
| 9:00 AM | `daily_pantry_check` | Fans out DailyPantryCheck to enabled households |
| 10:00 AM | `procurement_reminder` | Fans out ProcurementReminder to all non-off households |

### Fan-Out Pattern

`FeedMe.Scheduler` is the sole cron entry point. It queries households matching criteria (automation_tier != :off, feature enabled, matching day-of-week for weekly jobs) and enqueues one job per household into the specialized queue.

### Workers

**WeeklySuggestion** (`lib/feed_me/meal_planning/jobs/weekly_suggestion.ex`): Creates draft meal plan for the coming week by shuffling household recipes across days. Only runs for households with `automation_tier >= :recommend` and `weekly_suggestion_enabled`.

**DailyPantryCheck** (`lib/feed_me/procurement/jobs/daily_pantry_check.ex`): Creates procurement recommendations from items needing restock or expiring within 7 days. Skips if a suggested plan already exists today. Only for `automation_tier >= :recommend` and `daily_pantry_check_enabled`.

**ProcurementReminder** (`lib/feed_me/procurement/jobs/procurement_reminder.ex`): Sends PubSub notifications for suggested procurement plans older than 24 hours, prompting user review.

## Supervision Tree

```
FeedMe.Supervisor (one_for_one)
├── FeedMeWeb.Telemetry
├── FeedMe.Repo
├── DNSCluster
├── Phoenix.PubSub (name: FeedMe.PubSub)
├── Task.Supervisor (name: FeedMe.Pantry.SyncTaskSupervisor)
├── FeedMe.Pantry.Sync (GenServer - shopping→pantry debounce)
├── Oban (background job processor + cron)
└── FeedMeWeb.Endpoint
```

## Database

- All primary keys: binary UUID (`Ecto.UUID`).
- 21 migrations covering the full schema evolution.
- Embedded schemas: `FeedMe.Nutrition.Info` stored as JSONB on `pantry_items.nutrition` and `recipe_ingredients.nutrition`.
- Decimal type used for all quantities, prices, and nutrition values.
- Timezone stored per-household for schedule calculations.

### Key Relationships

```
Household
├── MealPlan (has_many)
│   └── MealPlanItem → Recipe
├── ProcurementPlan (has_many)
│   └── ProcurementItem → Pantry.Item, Supplier, Shopping.Item
├── Shopping.List (has_many)
│   ├── Shopping.Item → Pantry.Item, Category
│   └── ListShare → User (per-member sharing)
├── StorageLocation (has_many)
│   └── Pantry.Category (has_many, location-scoped)
├── Pantry.Item (has_many)
│   ├── → Category, StorageLocation
│   ├── nutrition (embedded Nutrition.Info)
│   └── Transaction (has_many, audit log)
├── Recipe (has_many)
│   ├── Ingredient → Pantry.Item, nutrition (embedded)
│   ├── Photo (has_many)
│   └── CookingLog (has_many)
├── Budget (has_many)
│   └── Budget.Transaction (has_many)
├── AI.Conversation (has_many)
│   ├── Message (has_many)
│   └── ConversationShare → User
├── HouseholdSupplier → Supplier
└── TasteProfile → User
```

## Real-Time (PubSub)

Each context that broadcasts follows the same pattern:

```elixir
def subscribe(household_id) do
  Phoenix.PubSub.subscribe(FeedMe.PubSub, "context:#{household_id}")
end

defp broadcast({:ok, record} = result, event) do
  Phoenix.PubSub.broadcast(FeedMe.PubSub, "context:#{record.household_id}", {event, record})
  result
end
```

| Context | Topic | Events |
|---------|-------|--------|
| Pantry | `"pantry:#{id}"` | Item/category CRUD, quantity changes |
| Shopping | `"shopping:#{id}"` | List/item CRUD |
| Shopping | `"shopping_list:#{list_id}"` | Per-list item updates |
| MealPlanning | `"meal_planning:#{id}"` | Plan/item CRUD |
| Procurement | `"procurement:#{id}"` | Plan/item CRUD, status changes |

## JavaScript Hooks

| Hook | File | Purpose |
|------|------|---------|
| barcode_scanner_hook | `assets/js/hooks/barcode_scanner_hook.js` | Camera-based barcode scanning for pantry items |
| camera_hook | `assets/js/hooks/camera_hook.js` | Photo capture/upload for recipes and AI vision |
| voice_input_hook | `assets/js/hooks/voice_input_hook.js` | Voice transcription via Web Speech API |
| chat_drawer_hook | `assets/js/hooks/chat_drawer_hook.js` | Scroll-to-bottom and Escape key for chat drawer |

Hooks are registered in `assets/js/hooks/index.js` and passed to the LiveSocket constructor.

### LiveView Hooks (Elixir)

**HouseholdHooks** (`lib/feed_me_web/live/household_hooks.ex`): `on_mount` callback that loads household + membership for scoped pages. Assigns `:household`, `:role`, `:nutrition_display`. Attaches chat drawer hooks.

**ChatDrawerHooks** (`lib/feed_me_web/live/chat_drawer_hooks.ex`): Uses `attach_hook` pattern to intercept drawer events (toggle, send, clear) and info messages (task completion) across all LiveViews in the household live_session. Manages ephemeral message state in socket assigns.
