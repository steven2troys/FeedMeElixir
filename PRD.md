Product Requirements Document (PRD): FeedMe
Version: 2.0
Status: Active Development
Target Platform: Web & Mobile (PWA/Responsive Web via Phoenix LiveView)

1. Executive Summary

FeedMe is an AI-powered household management application that streamlines grocery shopping, pantry inventory, meal planning, and procurement. Built on a Household-based multi-tenant architecture, FeedMe aggregates individual dietary preferences to generate intelligent recommendations, automates meal-to-shopping pipelines, tracks nutrition, and connects to grocery suppliers.

Key differentiators include a BYOK (Bring Your Own Key) AI model with 14 tool calls, real-time multi-device synchronization using Elixir/Phoenix PubSub, an agentic procurement system that creates supplier-linked shopping lists from meal plans, and configurable automation tiers that let households control how autonomously the AI operates.

2. User Roles & Authentication

2.1 Roles

Household Admin: The creator of the household.
Permissions: Manage budget, invite/remove members, configure AI API keys, set automation tier, approve AI "Purchase" agents, manage supplier integrations, configure scheduling.

Household Member: Invited users.
Permissions: Edit personal profile (taste profile, nutrition display preference), view/edit pantry, view/edit shopping lists (main + shared custom lists), use chat (persistent + drawer), add/cook recipes, view meal plans, view procurement plans.

2.2 Authentication & Onboarding

Method: Google OAuth 2.0 (via Ueberauth).
Flow:
- User signs in via Google.
- System checks if email belongs to an existing Household (checks pending invitations).
- If no, prompt to "Create Household" (user becomes Admin) or "Wait for Invite."
- If yes, load Household dashboard.

3. Core Features

3.1 Personal User Profiles (The "Taste Profile")

Each member maintains a profile that the AI uses as context for decision-making.
- Dietary Restrictions: (Multi-select) Vegan, Vegetarian, Keto, Gluten-Free, Lactose Intolerant, etc.
- Allergies: (Free text/Tagging) Peanuts, Shellfish, Soy.
- Dislikes: (Free text) Mushrooms, Cilantro, slimy textures, Indian food.
- Favorites: (Free text) Italian food, Pomegranates, Ribeye.
- Nutrition Display: (Select) None, Basic (calories + macros), Detailed (full micronutrients).
- AI Context: The AI cross-references all household member profiles when suggesting recipes, meal plans, and shopping items.

3.2 The Pantry (Inventory)

Data Structure:
- Name: String (includes unit context, e.g., "Gallon of Milk").
- Quantity: Decimal (precise math, no floating-point errors).
- Unit: String (e.g., "lbs", "oz", "count").
- Category: Belongs to a user-orderable category within a storage location.
- Storage Location: Multi-location support (On Hand, Pantry, Garage, Bulk Storage, Garden Shed, etc.).
- Expiration Date: Date.
- Always In Stock: Boolean.
- Restock Threshold: Decimal (defaults to 0).
- Nutrition: Embedded Nutrition.Info (JSONB) with calories, macros, micronutrients, serving size, source.
- Barcode: Optional, for quick scanning identification.

Logic:
- Auto-Restock: When Quantity <= Restock Threshold AND Always In Stock == True, trigger addition to Main Shopping List.
- Smart Entry: AI parses natural language input. If user inputs "4 cans of beans", AI sets Quantity: 4 and Name: Cans of beans.
- Multi-Location: Items belong to storage locations. Categories are location-scoped. Moving items between locations clears category. Default "On Hand" location cannot be deleted.
- Transaction Log: Every quantity change is recorded as a Transaction with user, reason, and timestamp for audit.
- Expiration Alerts: Items expiring within configurable days are surfaced for procurement or use.

3.3 Shopping Lists

Types: Main List (default for restock/procurement), Custom Lists (e.g., "Thanksgiving").
- Per-Member Sharing: Custom lists can be shared with specific household members via ListShare.
- Real-Time Sync: Updates are instantaneous across devices via PubSub. If User A adds an item, User B sees it appear immediately.
- Sorting/Layout:
  - Level 1: Sort by Category in a user-definable order (CategoryOrder per list).
  - Level 2: If supplier aisle info is available, sort by aisle location.
- Auto-Add to Pantry: Lists can be configured with an `auto_add_to_location_id` to automatically route checked items to a specific storage location.
- Fulfillment: Items can be synced from procurement plans. Checked items trigger AI-powered pantry sync (see Section 5.1).

3.4 Recipe Book

Structure: Title, Description, Ingredients (linked to pantry items), Instructions, Photos (carousel with primary photo), Tags.
Smart Interactions:
- "Cooked It" Button: Performs an atomic Ecto transaction, decrementing all linked ingredients from Pantry (quantity x servings multiplier). Creates a CookingLog entry with user, servings made, notes, and rating (1-5 stars).
- Add to List: AI compares recipe ingredients against pantry and adds missing items to the Shopping List.
- Nutrition: Per-ingredient embedded nutrition data. Recipe totals and per-serving calculations computed from ingredient nutrition.
- Photos: Multiple photos per recipe with sort order and primary photo selection.
- Cooking History: CookingLog tracks who cooked what, when, with ratings for recommendation improvement.

3.5 Meal Planning

Structure: MealPlan with start_date, end_date, status (draft/active/completed/archived), optional AI-generated flag.
- Items: MealPlanItem entries link to recipes with meal_type (breakfast/lunch/dinner/snack), planned_date, and optional custom servings.
- Shopping Needs: `calculate_shopping_needs` aggregates ingredient needs across all recipes (quantity x servings_multiplier), groups by (name, unit), then deducts current pantry stock. Returns only items where need > 0.
- AI Suggestions: Weekly suggestion job creates draft meal plans by shuffling household recipes, distributing across days.
- Status Workflow: draft → active → completed → archived.

3.6 Procurement System

The agentic procurement pipeline connects meal plans to supplier-linked shopping lists.
- Sources: Plans can be created from meal plans (`create_from_meal_plan`), restock needs (`create_from_restock`), or expiring items (`create_from_expiring`).
- Items: ProcurementItem with estimated_price, actual_price, category, deep_link_url, links to pantry_item, supplier, and shopping_item.
- Status Workflow:
  - Plan: suggested → approved (with approved_by user) → shopping → fulfilled (with actual_total) or cancelled.
  - Item: needed → in_cart (synced to shopping list) → purchased (with actual_price) or skipped.
- Budget Check: `check_budget` sums estimated prices of non-skipped items before approval.
- Shopping Sync: `sync_to_shopping_list` creates Shopping.Items from procurement items with status :needed, updates their status to :in_cart with shopping_item_id link.
- Supplier Deep Links: Each item gets a clickable search URL to the household's default supplier.

3.7 Suppliers

Global Defaults: Instacart, Amazon Fresh, Walmart, Kroger, Target (seeded at startup with search URL templates).
- Custom Suppliers: Households can create custom suppliers.
- Household Enabling: Households enable suppliers via HouseholdSupplier records. One supplier can be marked as default.
- Deep Link Generation: `generate_deep_link(supplier, product_name)` replaces `{query}` placeholder in supplier's `deep_link_search_template` with URL-encoded product name.
- Future API Integration: Stub functions exist for `search_products`, `get_product_price`, `add_to_cart`, and `get_aisle_info` for eventual supplier API integration.

3.8 Nutrition Tracking

Embedded Data: Nutrition.Info schema stored as JSONB on pantry items and recipe ingredients.
- Fields (all Decimal): calories, protein_g, carbs_g, fat_g, saturated_fat_g, fiber_g, sugar_g, sodium_mg, cholesterol_mg, vitamin_a_mcg, vitamin_c_mg, vitamin_d_mcg, vitamin_k_mcg, calcium_mg, iron_mg, potassium_mg. Plus serving_size (string) and source (e.g., "ai_estimated").
- AI Estimation: Batch estimation processes 20 items per API call via `backfill_pantry_items` and `backfill_recipe_ingredients`. Individual estimation via the `estimate_nutrition` AI tool.
- Recipe Calculations: `recipe_total` sums nutrition across all ingredients. `recipe_per_serving` divides by servings (rounded to 1 decimal).
- Display Tiers: Configurable per user via taste profile:
  - "none" - No nutrition displayed.
  - "basic" - Calories, protein, carbs, fat only.
  - "detailed" - Full macro and micronutrient breakdown.

3.9 Budgeting & Finance

Controls: Admin sets a weekly/monthly budget limit (amount + currency + period).
AI Authority Levels:
- Recommend: AI fills cart/suggests items but cannot checkout. (`ai_can_auto_add?`)
- Purchase: AI can execute checkout if within budget. (`ai_can_auto_purchase?`, `within_budget?`)
Budget Analysis: `get_period_spending`, `get_remaining`, `alert_threshold_exceeded?`, `get_budget_summary`.
Procurement Integration: Budget checks during procurement plan approval.

3.10 Utilities

- Unit Converter: Dedicated UI tab or AI prompt helper to convert measurements.
- Barcode Scanner: Camera-based barcode scanning to quickly identify and add pantry items.

4. AI & Chat Interface (The "Brain")

4.1 Configuration

BYOK (Bring Your Own Key): Admin inputs API keys in Settings. Keys are encrypted at rest via Cloak.Ecto.
Model Selection: Dropdown fetching available models from OpenRouter. Filter shows only models supporting tools and vision.
Key Management: Keys are validated on save, touched (last_used_at) on use, and marked invalid on auth failure.

4.2 Interaction Modes

Text: Standard chat with markdown rendering.
Voice (Dictation): Client-side processing via Web Speech API. Tap-to-toggle microphone. Auto-stop after silence detection.
Vision (Camera/Upload): Photo analysis for inventory ("What can I cook with this?"), macros estimation, recipe digitization.

4.3 Chat Modes

Persistent Chat: Full conversations saved to database (Conversation + Message schemas). Supports sharing between household members via ConversationShare. Streaming responses via OpenRouter SSE.

Ephemeral Chat (Drawer): FAB button + sliding panel available on all household pages. Messages live in socket assigns only (no DB persistence). Context-aware system prompts based on current page (pantry, shopping, recipes). Uses Task.Supervisor for async AI calls. Cleared on drawer close.

4.4 AI Tools (14 functions)

Pantry: add_to_pantry, check_pantry, get_pantry_categories, estimate_nutrition.
Shopping: add_to_shopping_list.
Recipes: search_recipes, suggest_recipe, add_recipe.
Meal Planning: suggest_meal_plan.
Procurement: create_procurement_plan, sync_procurement_to_shopping_list, get_supplier_link.
Profiles: get_taste_profiles.
Web: search_web (via Perplexity Sonar on OpenRouter).

All tools receive context `%{household_id:, user:}` and operate within household scope.

5. Automation & Scheduling

5.1 Pantry Sync (GenServer)

FeedMe.Pantry.Sync is a GenServer that debounces checked shopping items into batched AI pantry updates.
- Queue: Items keyed by {household_id, storage_location_id}, deduplicated by shopping_item_id.
- Debounce: 10 minutes (production), 30 seconds (dev), disabled (test).
- Execution: Spawns Task via SyncTaskSupervisor. AI loop (max 3 rounds) fuzzy-matches items to pantry, converts units, creates/updates items with nutrition.

5.2 Automation Tiers

Household-level setting controlling AI autonomy:
- off (default): No automated actions.
- recommend: AI suggests items/meals, user must approve.
- cart_fill: AI auto-fills shopping carts (requires approval before checkout).
- auto_purchase: AI makes purchases automatically (budget permitting).

5.3 Oban Background Jobs

Queues: default (10 workers), procurement (5), meal_planning (5).

Cron Schedule (via Oban.Plugins.Cron):
- 8:00 AM UTC: Weekly Suggestion Dispatcher (checks per-household day setting).
- 9:00 AM UTC: Daily Pantry Check Dispatcher.
- 10:00 AM UTC: Procurement Reminder Dispatcher.

Workers:
- FeedMe.Scheduler: Cron dispatcher. Queries eligible households (automation_tier != :off + feature enabled) and enqueues per-household jobs.
- FeedMe.MealPlanning.Jobs.WeeklySuggestion: Creates draft meal plans by shuffling recipes across the coming week. Max 3 attempts.
- FeedMe.Procurement.Jobs.DailyPantryCheck: Creates procurement recommendations from restock/expiring items. Skips if suggestion already exists today. Max 3 attempts.
- FeedMe.Procurement.Jobs.ProcurementReminder: Sends PubSub notifications for suggested plans older than 24 hours. Max 3 attempts.

6. Technical Architecture

6.1 Tech Stack

- Backend: Elixir 1.15+, Phoenix 1.8, PostgreSQL.
- Frontend: Phoenix LiveView 1.1, Tailwind CSS v4.
- AI: OpenRouter API via Req (streaming SSE + tool calling).
- Background Jobs: Oban 2.18+ with cron plugin and pruner.
- Auth: Google OAuth 2.0 via Ueberauth.
- Encryption: Cloak.Ecto for API key storage.
- Timezone: Tz library for per-household timezone support.
- HTTP: Req (not HTTPoison/Tesla).

6.2 Key Integrations

- Google OAuth: Authentication.
- OpenRouter: AI model access (Claude, GPT-4, Gemini, Perplexity Sonar).
- Supplier Deep Links: Instacart, Amazon Fresh, Walmart, Kroger, Target search URL templates.

6.3 Database

- All schemas use binary UUID primary keys.
- 21 migrations covering auth, households, pantry, shopping, recipes, AI, budgets, suppliers, meal planning, procurement, Oban, and scheduling settings.
- Embedded schemas: Nutrition.Info (JSONB on pantry items and recipe ingredients).
- Multi-tenant: All data scoped to households via foreign keys.

7. Gap Analysis & Planned Features

Implemented:
- "Cooked It" atomic pantry decrement with cooking logs and ratings.
- AI-powered pantry sync from shopping lists (GenServer + Task.Supervisor).
- Multi-location storage with location-scoped categories.
- Per-member shopping list sharing.
- Nutrition tracking with AI estimation and display tiers.
- Meal planning with shopping needs calculation.
- Agentic procurement pipeline with supplier deep links.
- Automation tiers and Oban cron scheduling.
- Persistent + ephemeral AI chat with 14 tools.

Planned:
- Supplier API integrations: Live product search, pricing, and cart management (stubs exist).
- Payment gateway: Stripe for SaaS subscription and auto_purchase budget integration.
- Offline access: Local storage caching for read-only list access when connection is lost.
- Recipe sharing: Cross-household recipe sharing and public recipe links.
- Advanced analytics: Spending trends, nutrition tracking over time, cooking frequency insights.
