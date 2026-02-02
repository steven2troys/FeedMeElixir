Product Requirements Document (PRD): FeedMe
Version: 1.1
Status: Ready for Development
Target Platform: Web & Mobile (PWA/Responsive Web via Phoenix LiveView)
1. Executive Summary
FeedMe is an AI-powered household management application designed to streamline grocery shopping, pantry inventory, and meal planning. By leveraging a Household-based architecture, FeedMe aggregates individual dietary preferences to generate intelligent recommendations. It features a conversational AI interface capable of vision and voice interaction to manage inventory, generate recipes from images, and automate purchasing via third-party suppliers.
Key differentiators include a BYOK (Bring Your Own Key) AI model, real-time synchronization using Elixir/Phoenix, and a simplified "Standard Item" approach to inventory management.
2. User Roles & Authentication
2.1 Roles
Household Admin: The creator of the household.
Permissions: Manage Billing/Budget, invite/remove members, configure AI API Keys, approve AI "Purchase" agents, manage Supplier integrations.
Household Member: Invited users.
Permissions: Edit personal profile, view/edit Pantry, view/edit Shopping Lists, use Chat, add Recipes.
2.2 Authentication & Onboarding
Method: Google OAuth 2.0.
Flow:
User signs in via Google.
System checks if email belongs to an existing Household.
If no, prompt to "Create Household" (User becomes Admin) or "Wait for Invite."
If yes, load Household dashboard.
3. Core Features
3.1 Personal User Profiles (The "Taste Profile")
Each member maintains a profile that the AI uses as context for decision-making.
Dietary Restrictions: (Multi-select) Vegan, Vegetarian, Keto, Gluten-Free, Lactose Intolerant, etc.
Allergies: (Free text/Tagging) Peanuts, Shellfish, Soy.
Dislikes: (Free text) Mushrooms, Cilantro, slimy textures, Indian food.
Favorites: (Free text) Italian food, Pomegranates, Ribeye.
AI Context: The AI must cross-reference these profiles when suggesting recipes (e.g., "Suggest a dinner for the whole house, but exclude mushrooms for Bob").
3.2 The Pantry (Inventory)
Data Structure:
Name: String (includes unit, e.g., "Gallon of Milk").
Quantity: Decimal.
Expiration Date: Date.
Always In Stock: Boolean.
Restock Threshold: Decimal (Defaults to 0).
Is Standard: Boolean. (Designates the item as the canonical version for the household to prevent duplicates).
Logic:
Auto-Restock: When Quantity <= Restock Threshold AND Always In Stock == True → Trigger: Add item to Main Shopping List.
Smart Entry: AI parses natural language input. If user inputs "4 cans of beans", AI sets Quantity: 4 and Name: Cans of beans.
3.3 Shopping Lists
Types: Main List (default for restock), Custom Lists (e.g., "Thanksgiving").
Real-Time Sync: CRITICAL. Updates must be instantaneous across devices (using Phoenix Channels). If User A adds an item, User B sees it appear immediately without refreshing.
Sorting/Layout:
Level 1: Sort by Category (Produce, Dairy, Frozen) in a user-definable order.
Level 2: If Supplier API is available (e.g., Fred Meyer), sort by actual aisle location.
Fulfillment:
Admin can direct AI to search/purchase from approved Suppliers.
Options: Delivery or Pickup.
3.4 Recipe Book
Structure: Title, Description, Ingredients, Instructions, Photos (Carousel).
Smart Interactions:
"Cooked It" Button: Performs an atomic transaction, decrementing all linked ingredients from the Pantry count.
Add to List: User selects a recipe; AI compares ingredients against Pantry and adds missing items to the Shopping List.
3.5 Budgeting & Finance
Controls: Admin sets a weekly/monthly budget limit.
AI Authority Levels:
Recommend: AI fills cart/suggests items but cannot checkout.
Purchase: AI can execute checkout if total cost < Budget Remaining.
3.6 Utilities
Unit Converter: Dedicated UI tab or AI prompt helper to convert measurements (e.g., cups to ounces).
Barcode Scanner: Mobile-only feature using device camera to quickly identify and add items.
4. AI & Chat Interface (The "Brain")
4.1 Configuration
BYOK (Bring Your Own Key): Admin inputs API keys in Settings.
Model Selection: Dropdown fetching available models.
Filter: UI only displays models that support Tools and Vision.
4.2 Interaction Modes
Text: Standard chat.
Voice (Dictation):
Tech: Client-side processing (WASM/Edge) for low latency.
UX: Tap-to-toggle microphone.
Auto-Stop: Automatically stops recording after >3 seconds of silence.
Vision (Camera/Upload):
Inventory: "What can I cook with this?" (Photo of fridge).
Analysis: "What are the macros in this?" (Photo of dish).
Digitization: "Add this to my recipes." (Photo of physical recipe card).
5. Technical Architecture
5.1 Tech Stack
Backend: Elixir (Phoenix Framework).
Why: Superior concurrency for real-time list sync (Phoenix Channels) and fault tolerance.
Frontend: Phoenix LiveView.
Why: Enables real-time interactivity and cross-platform deployment (Web + Mobile via LiveView Native or wrapper) with a single codebase.
Database: PostgreSQL.
Extension: pgvector (optional) for semantic search of recipes.
Voice Processing: OpenAI Whisper (WASM).
Running on the client/edge to minimize latency and server costs.
5.2 Key Integrations
Google OAuth: For authentication.
Supplier APIs: For store layout data (where available).
Payment Gateway: Stripe (for SaaS subscription and potential budget management integrations).
6. Gap Analysis & Mitigation
Pantry Decrement Friction:
Solution: The "Cooked It" button is the primary driver for inventory accuracy, reducing the need for manual "-1" updates on every item.
Ingredient Matching:
Solution: When "Cooking" a recipe, AI presents a confirmation modal: "Deducting 2 onions and 1 cup of rice. Confirm?" allowing the user to override quantities before database update.
Offline Access:
Solution: While Phoenix LiveView requires connection, use live_view_native or local storage caching strategies to allow read-only access to lists when signal is lost in a grocery store.
