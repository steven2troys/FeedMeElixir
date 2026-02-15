# Auto-Restock: Pantry to Shopping List - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically add keep-in-stock pantry items to the shopping list when they drop below threshold, and prompt users to add non-keep-in-stock items when they run out.

**Architecture:** Hook-based approach using `attach_hook/4` in the household `live_session`. RestockHooks subscribes to Pantry PubSub and intercepts `:restock_needed` and `:item_depleted` broadcasts. Keep-in-stock items auto-add via `Shopping.add_from_pantry/4`. Non-keep-in-stock items populate a `:restock_prompts` assign rendered inline on pantry pages or as toasts elsewhere.

**Tech Stack:** Phoenix LiveView hooks, PubSub, Ecto queries, daisyUI components, JS hook for toast auto-dismiss.

---

### Task 1: Add `:item_depleted` broadcast to Pantry.adjust_quantity

Currently `:restock_needed` only fires for `always_in_stock` items. We need a new `:item_depleted` event for non-keep-in-stock items that hit zero.

**Files:**
- Modify: `lib/feed_me/pantry.ex:554-556`
- Test: `test/feed_me/pantry_test.exs`

**Step 1: Write the failing test**

Add to the existing pantry test file, in the quantity adjustment describe block:

```elixir
test "adjust_quantity broadcasts :item_depleted when non-stock item reaches zero" do
  # Setup: create item with always_in_stock: false, quantity: 1
  # Subscribe to PubSub
  # Adjust by -1
  # Assert receive {:item_depleted, %Item{quantity: 0}}
end

test "adjust_quantity does NOT broadcast :item_depleted for always_in_stock items" do
  # Setup: create item with always_in_stock: true, quantity: 1, restock_threshold: 2
  # Subscribe to PubSub
  # Adjust by -1
  # Assert receive {:restock_needed, _} (not :item_depleted)
  # refute_receive {:item_depleted, _}
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/feed_me/pantry_test.exs --only depleted -v`
Expected: FAIL

**Step 3: Implement the broadcast**

In `lib/feed_me/pantry.ex`, after the existing `:restock_needed` broadcast (line 554-556), add:

```elixir
if not item.always_in_stock and
     Decimal.compare(quantity_after, Decimal.new(0)) == :eq and
     Decimal.compare(quantity_before, Decimal.new(0)) == :gt do
  broadcast(:pantry, item.household_id, {:item_depleted, updated_item})
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/feed_me/pantry_test.exs --only depleted -v`
Expected: PASS

**Step 5: Commit**

```
git add lib/feed_me/pantry.ex test/feed_me/pantry_test.exs
git commit -m "Add :item_depleted broadcast for non-stock items hitting zero"
```

---

### Task 2: Add Shopping.item_on_list?/2

Dedup function to check if a pantry item is already on a shopping list (unchecked items only).

**Files:**
- Modify: `lib/feed_me/shopping.ex`
- Test: `test/feed_me/shopping_test.exs`

**Step 1: Write the failing test**

```elixir
describe "item_on_list?/2" do
  test "returns true when pantry item is on the list (unchecked)", %{household: household, user: user} do
    pantry_item = PantryFixtures.item_fixture(household, %{name: "Milk"})
    list = Shopping.get_or_create_main_list(household.id)
    Shopping.add_from_pantry(list.id, pantry_item, Decimal.new("1"), user)

    assert Shopping.item_on_list?(list.id, pantry_item.id)
  end

  test "returns false when pantry item is not on the list", %{household: household} do
    pantry_item = PantryFixtures.item_fixture(household, %{name: "Milk"})
    list = Shopping.get_or_create_main_list(household.id)

    refute Shopping.item_on_list?(list.id, pantry_item.id)
  end

  test "returns false when pantry item is on the list but checked", %{household: household, user: user} do
    pantry_item = PantryFixtures.item_fixture(household, %{name: "Milk"})
    list = Shopping.get_or_create_main_list(household.id)
    {:ok, item} = Shopping.add_from_pantry(list.id, pantry_item, Decimal.new("1"), user)
    Shopping.toggle_item_checked(item, user.id)

    refute Shopping.item_on_list?(list.id, pantry_item.id)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/feed_me/shopping_test.exs --only item_on_list -v`
Expected: FAIL (function doesn't exist)

**Step 3: Implement**

In `lib/feed_me/shopping.ex`, add:

```elixir
@doc """
Checks if a pantry item is already on a shopping list (unchecked only).
"""
def item_on_list?(shopping_list_id, pantry_item_id) do
  Item
  |> where([i], i.shopping_list_id == ^shopping_list_id)
  |> where([i], i.pantry_item_id == ^pantry_item_id)
  |> where([i], i.checked == false)
  |> Repo.exists?()
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/feed_me/shopping_test.exs --only item_on_list -v`
Expected: PASS

**Step 5: Commit**

```
git add lib/feed_me/shopping.ex test/feed_me/shopping_test.exs
git commit -m "Add Shopping.item_on_list?/2 for dedup checking"
```

---

### Task 3: Create RestockHooks module

Core hook logic: subscribes to PubSub, handles `:restock_needed` (auto-add) and `:item_depleted` (prompt).

**Files:**
- Create: `lib/feed_me_web/live/restock_hooks.ex`
- Test: `test/feed_me_web/live/restock_hooks_test.exs`

**Step 1: Write the failing test**

Test the `attach_restock_hooks/1` function initializes assigns and that the info handlers work correctly. Use the PubSub broadcast approach to test handlers:

```elixir
defmodule FeedMeWeb.RestockHooksTest do
  use FeedMeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FeedMe.Shopping
  alias FeedMe.Pantry

  # Test via the pantry LiveView which has RestockHooks attached
  setup do
    user = FeedMe.AccountsFixtures.user_fixture()
    household = FeedMe.HouseholdsFixtures.household_fixture(%{}, user)
    location = Pantry.get_pantry_location(household.id)
    %{user: user, household: household, location: location}
  end

  describe "keep-in-stock auto-add" do
    test "auto-adds to shopping list when keep-in-stock item hits threshold",
         %{conn: conn, user: user, household: household, location: location} do
      pantry_item =
        FeedMe.PantryFixtures.item_fixture(household, %{
          name: "Milk",
          quantity: Decimal.new("3"),
          always_in_stock: true,
          restock_threshold: Decimal.new("2")
        })

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/households/#{household.id}/pantry/locations/#{location.id}")

      # Trigger restock by adjusting quantity below threshold
      Pantry.adjust_quantity(pantry_item, Decimal.new("-2"), user, reason: "test")

      # Give the hook time to process
      _ = render(view)

      # Check that item was auto-added to shopping list
      main_list = Shopping.get_or_create_main_list(household.id)
      assert Shopping.item_on_list?(main_list.id, pantry_item.id)
    end
  end

  describe "item depleted prompt" do
    test "adds depleted non-stock item to restock_prompts",
         %{conn: conn, user: user, household: household, location: location} do
      pantry_item =
        FeedMe.PantryFixtures.item_fixture(household, %{
          name: "Avocados",
          quantity: Decimal.new("1"),
          always_in_stock: false
        })

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/households/#{household.id}/pantry/locations/#{location.id}")

      # Deplete the item
      Pantry.adjust_quantity(pantry_item, Decimal.new("-1"), user, reason: "test")

      # The prompt should appear in the rendered output
      html = render(view)
      assert html =~ "Add to list?"
      assert html =~ "Avocados"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/feed_me_web/live/restock_hooks_test.exs -v`
Expected: FAIL (module doesn't exist)

**Step 3: Implement RestockHooks**

Create `lib/feed_me_web/live/restock_hooks.ex`:

```elixir
defmodule FeedMeWeb.RestockHooks do
  @moduledoc """
  LiveView hooks for auto-restock: adds keep-in-stock items to shopping list
  automatically, and prompts users to add depleted items.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias FeedMe.Pantry
  alias FeedMe.Shopping

  def attach_restock_hooks(socket) do
    household = socket.assigns[:household]

    if household && connected?(socket) do
      Pantry.subscribe(household.id)
    end

    socket
    |> assign(:restock_prompts, %{})
    |> assign(:on_pantry_page, false)
    |> attach_hook(:restock_info, :handle_info, &handle_info/2)
    |> attach_hook(:restock_events, :handle_event, &handle_event/3)
  end

  defp handle_info({:restock_needed, item}, socket) do
    household = socket.assigns.household
    user = socket.assigns.current_scope.user
    main_list = Shopping.get_or_create_main_list(household.id)

    if Shopping.item_on_list?(main_list.id, item.id) do
      {:halt, socket}
    else
      threshold = item.restock_threshold || Decimal.new(0)
      quantity_needed = Decimal.sub(threshold, item.quantity)
      quantity_needed =
        if Decimal.compare(quantity_needed, Decimal.new(0)) == :gt,
          do: quantity_needed,
          else: Decimal.new("1")

      case Shopping.add_from_pantry(main_list.id, item, quantity_needed, user) do
        {:ok, _shopping_item} ->
          {:halt, put_flash(socket, :info, "Added #{item.name} (x#{quantity_needed}) to shopping list")}

        {:error, _reason} ->
          {:halt, socket}
      end
    end
  end

  defp handle_info({:item_depleted, item}, socket) do
    household = socket.assigns.household
    main_list = Shopping.get_or_create_main_list(household.id)

    if Shopping.item_on_list?(main_list.id, item.id) do
      {:halt, socket}
    else
      prompts = Map.put(socket.assigns.restock_prompts, item.id, %{
        id: item.id,
        name: item.name,
        unit: item.unit
      })

      {:halt, assign(socket, :restock_prompts, prompts)}
    end
  end

  defp handle_info(_msg, socket), do: {:cont, socket}

  defp handle_event("add_to_shopping", %{"item-id" => pantry_item_id}, socket) do
    household = socket.assigns.household
    user = socket.assigns.current_scope.user

    case Pantry.get_item(pantry_item_id, household.id) do
      nil ->
        {:halt, socket}

      pantry_item ->
        main_list = Shopping.get_or_create_main_list(household.id)

        unless Shopping.item_on_list?(main_list.id, pantry_item.id) do
          Shopping.add_from_pantry(main_list.id, pantry_item, Decimal.new("1"), user)
        end

        prompts = Map.delete(socket.assigns.restock_prompts, pantry_item_id)

        {:halt,
         socket
         |> assign(:restock_prompts, prompts)
         |> put_flash(:info, "Added #{pantry_item.name} to shopping list")}
    end
  end

  defp handle_event("dismiss_restock", %{"item-id" => pantry_item_id}, socket) do
    prompts = Map.delete(socket.assigns.restock_prompts, pantry_item_id)
    {:halt, assign(socket, :restock_prompts, prompts)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/feed_me_web/live/restock_hooks_test.exs -v`
Expected: FAIL (hook not wired up yet - Task 4 will fix this)

**Step 5: Commit**

```
git add lib/feed_me_web/live/restock_hooks.ex test/feed_me_web/live/restock_hooks_test.exs
git commit -m "Add RestockHooks module for auto-restock logic"
```

---

### Task 4: Wire up RestockHooks and fix PubSub subscription

Attach RestockHooks in HouseholdHooks. Remove duplicate Pantry.subscribe from PantryLive.Index (RestockHooks now subscribes). Update PantryLive to set `:on_pantry_page` and remove its `:restock_needed` handler (hook handles it).

**Files:**
- Modify: `lib/feed_me_web/live/household_hooks.ex:34`
- Modify: `lib/feed_me_web/live/pantry_live/index.ex:14,308-310`

**Step 1: Attach RestockHooks in HouseholdHooks**

In `lib/feed_me_web/live/household_hooks.ex`, line 34, chain `attach_restock_hooks` after `attach_chat_drawer`:

```elixir
# Change line 34 from:
|> FeedMeWeb.ChatDrawerHooks.attach_chat_drawer()}
# To:
|> FeedMeWeb.ChatDrawerHooks.attach_chat_drawer()
|> FeedMeWeb.RestockHooks.attach_restock_hooks()}
```

**Step 2: Remove duplicate PubSub subscription from PantryLive.Index**

In `lib/feed_me_web/live/pantry_live/index.ex`, line 14, remove:
```elixir
if connected?(socket), do: Pantry.subscribe(household.id)
```

**Step 3: Set `:on_pantry_page` in PantryLive.Index mount**

In `lib/feed_me_web/live/pantry_live/index.ex` mount, add to the assign chain:
```elixir
|> assign(:on_pantry_page, true)
```

**Step 4: Remove `:restock_needed` handler from PantryLive.Index**

In `lib/feed_me_web/live/pantry_live/index.ex`, remove lines 308-310:
```elixir
def handle_info({:restock_needed, item}, socket) do
  {:noreply, put_flash(socket, :info, "#{item.name} needs restocking!")}
end
```

**Step 5: Run the restock hooks test**

Run: `mix test test/feed_me_web/live/restock_hooks_test.exs -v`
Expected: PASS

**Step 6: Run full test suite**

Run: `mix test`
Expected: All pass (except pre-existing ai_test failure)

**Step 7: Commit**

```
git add lib/feed_me_web/live/household_hooks.ex lib/feed_me_web/live/pantry_live/index.ex
git commit -m "Wire up RestockHooks in household live_session"
```

---

### Task 5: Add inline restock prompt to PantryLive.Index

Show "Add to list?" badge on item rows for depleted items.

**Files:**
- Modify: `lib/feed_me_web/live/pantry_live/index.ex` (template, around line 506)

**Step 1: Add inline prompt UI**

In the pantry item template, after line 506 (end of metadata div), before the closing `</div>` of `flex-1`, add:

```heex
<%= if Map.has_key?(@restock_prompts, item.id) do %>
  <div class="flex items-center gap-2 mt-1">
    <span class="badge badge-warning badge-sm gap-1">
      <.icon name="hero-exclamation-triangle" class="size-3" />
      Out of stock
    </span>
    <button
      phx-click="add_to_shopping"
      phx-value-item-id={item.id}
      class="badge badge-sm badge-info cursor-pointer gap-1"
    >
      <.icon name="hero-shopping-cart" class="size-3" />
      Add to list
    </button>
    <button
      phx-click="dismiss_restock"
      phx-value-item-id={item.id}
      class="badge badge-sm badge-ghost cursor-pointer"
    >
      <.icon name="hero-x-mark" class="size-3" />
    </button>
  </div>
<% end %>
```

**Step 2: Run the depleted prompt test**

Run: `mix test test/feed_me_web/live/restock_hooks_test.exs -v`
Expected: PASS (the "Add to list?" text should now appear)

**Step 3: Commit**

```
git add lib/feed_me_web/live/pantry_live/index.ex
git commit -m "Add inline restock prompt on pantry item rows"
```

---

### Task 6: Add restock toast component to household layout

For non-pantry pages, render restock prompts as floating toasts.

**Files:**
- Create: `lib/feed_me_web/components/restock_prompt.ex`
- Modify: `lib/feed_me_web/components/layouts/household.html.heex:104`
- Create: `assets/js/hooks/restock_toast_hook.js`
- Modify: `assets/js/hooks/index.js`

**Step 1: Create the restock prompt component**

Create `lib/feed_me_web/components/restock_prompt.ex`:

```elixir
defmodule FeedMeWeb.RestockPrompt do
  use Phoenix.Component

  import FeedMeWeb.CoreComponents, only: [icon: 1]

  attr :restock_prompts, :map, required: true
  attr :on_pantry_page, :boolean, default: false

  def restock_toasts(assigns) do
    ~H"""
    <div
      :if={@restock_prompts != %{} and not @on_pantry_page}
      class="fixed bottom-20 md:bottom-4 right-4 z-50 flex flex-col gap-2"
    >
      <div
        :for={{item_id, prompt} <- @restock_prompts}
        id={"restock-toast-#{item_id}"}
        phx-hook="RestockToast"
        class="alert alert-warning shadow-lg w-80 animate-slide-in-right"
      >
        <div class="flex items-center justify-between w-full gap-2">
          <span class="text-sm font-medium truncate">{prompt.name} is out</span>
          <div class="flex gap-1 flex-shrink-0">
            <button
              phx-click="add_to_shopping"
              phx-value-item-id={item_id}
              class="btn btn-xs btn-info"
            >
              Add to list
            </button>
            <button
              phx-click="dismiss_restock"
              phx-value-item-id={item_id}
              class="btn btn-xs btn-ghost"
            >
              <.icon name="hero-x-mark" class="size-3" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
```

**Step 2: Add to household layout**

In `lib/feed_me_web/components/layouts/household.html.heex`, after line 104 (`{@inner_content}`), add:

```heex
<FeedMeWeb.RestockPrompt.restock_toasts
  restock_prompts={assigns[:restock_prompts] || %{}}
  on_pantry_page={assigns[:on_pantry_page] || false}
/>
```

**Step 3: Create JS hook for auto-dismiss**

Create `assets/js/hooks/restock_toast_hook.js`:

```javascript
const RestockToast = {
  mounted() {
    this.timer = setTimeout(() => {
      this.el.classList.add("opacity-0", "transition-opacity", "duration-500");
      setTimeout(() => {
        this.pushEvent("dismiss_restock", { "item-id": this.el.id.replace("restock-toast-", "") });
      }, 500);
    }, 30000);
  },

  destroyed() {
    if (this.timer) clearTimeout(this.timer);
  }
};

export default RestockToast;
```

**Step 4: Register hook in assets/js/hooks/index.js**

Add import and export for `RestockToast`.

**Step 5: Commit**

```
git add lib/feed_me_web/components/restock_prompt.ex lib/feed_me_web/components/layouts/household.html.heex assets/js/hooks/restock_toast_hook.js assets/js/hooks/index.js
git commit -m "Add restock toast component for non-pantry pages"
```

---

### Task 7: Full integration test and cleanup

Run all tests, fix any issues, verify the complete flow.

**Step 1: Run full test suite**

Run: `mix test`
Expected: All pass (except pre-existing ai_test:177 failure)

**Step 2: Run precommit**

Run: `mix precommit`
Expected: PASS (compile warnings-as-errors, format, tests)

**Step 3: Fix any issues found**

Address compiler warnings, formatting issues, or test failures.

**Step 4: Final commit if needed**

```
git add -A
git commit -m "Fix lint/test issues from auto-restock feature"
```

---

## File Summary

| Action | File |
|--------|------|
| Modify | `lib/feed_me/pantry.ex` (add `:item_depleted` broadcast) |
| Modify | `lib/feed_me/shopping.ex` (add `item_on_list?/2`) |
| Create | `lib/feed_me_web/live/restock_hooks.ex` (hook module) |
| Modify | `lib/feed_me_web/live/household_hooks.ex` (attach hook) |
| Modify | `lib/feed_me_web/live/pantry_live/index.ex` (inline prompt, remove subscription & handler) |
| Create | `lib/feed_me_web/components/restock_prompt.ex` (toast component) |
| Modify | `lib/feed_me_web/components/layouts/household.html.heex` (render toasts) |
| Create | `assets/js/hooks/restock_toast_hook.js` (auto-dismiss) |
| Modify | `assets/js/hooks/index.js` (register hook) |
| Create | `test/feed_me_web/live/restock_hooks_test.exs` (integration tests) |
| Modify | `test/feed_me/pantry_test.exs` (depleted broadcast test) |
| Modify | `test/feed_me/shopping_test.exs` (item_on_list? tests) |
