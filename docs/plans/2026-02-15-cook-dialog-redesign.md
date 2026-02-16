# Cook Dialog Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the "Cook It" button and modal to show ingredient availability, let users add missing items to shopping list, and make the button's purpose clearer.

**Architecture:** Add a pure `Recipes.check_availability/2` function that compares recipe ingredients against pantry stock. The cook modal (`apply_action :cook`) precomputes availability and passes it to the template. The template groups ingredients by status and offers two actions: "Add Missing to List" and "Cooked It!". Servings changes recompute availability via a new event handler.

**Tech Stack:** Elixir, Phoenix LiveView 1.1, Ecto, DaisyUI/Tailwind

---

### Task 1: Add `Recipes.check_availability/2`

A pure function that takes a recipe (with ingredients preloaded) and servings count, returns availability data for each ingredient.

**Files:**
- Modify: `lib/feed_me/recipes.ex` (add function after `cook_recipe/3`, around line 310)
- Test: `test/feed_me/recipes_test.exs` (add new describe block)

**Step 1: Write the failing test**

Add to `test/feed_me/recipes_test.exs`:

```elixir
describe "check_availability" do
  setup do
    user = AccountsFixtures.user_fixture()
    household = HouseholdsFixtures.household_fixture(%{}, user)
    recipe = RecipesFixtures.recipe_fixture(household, %{servings: 4})
    %{user: user, household: household, recipe: recipe}
  end

  test "returns :have when pantry has enough", %{recipe: recipe, household: household} do
    pantry_item =
      PantryFixtures.item_fixture(household, %{name: "Chicken", quantity: Decimal.new("10")})

    RecipesFixtures.ingredient_fixture(recipe, %{
      name: "Chicken",
      pantry_item_id: pantry_item.id,
      quantity: Decimal.new("2")
    })

    recipe = Recipes.get_recipe(recipe.id, household.id)
    availability = Recipes.check_availability(recipe, 4)

    assert length(availability) == 1
    [item] = availability
    assert item.status == :have
    assert Decimal.equal?(item.have, Decimal.new("10"))
    assert Decimal.equal?(item.need, Decimal.new("2"))
  end

  test "returns :need when pantry is insufficient", %{recipe: recipe, household: household} do
    pantry_item =
      PantryFixtures.item_fixture(household, %{name: "Butter", quantity: Decimal.new("1")})

    RecipesFixtures.ingredient_fixture(recipe, %{
      name: "Butter",
      pantry_item_id: pantry_item.id,
      quantity: Decimal.new("4")
    })

    recipe = Recipes.get_recipe(recipe.id, household.id)
    availability = Recipes.check_availability(recipe, 4)

    [item] = availability
    assert item.status == :need
    assert Decimal.equal?(item.have, Decimal.new("1"))
    assert Decimal.equal?(item.need, Decimal.new("4"))
  end

  test "scales needed quantity by servings", %{recipe: recipe, household: household} do
    pantry_item =
      PantryFixtures.item_fixture(household, %{name: "Rice", quantity: Decimal.new("5")})

    # Recipe serves 4, ingredient is 4 cups (1 cup per serving)
    RecipesFixtures.ingredient_fixture(recipe, %{
      name: "Rice",
      pantry_item_id: pantry_item.id,
      quantity: Decimal.new("4")
    })

    recipe = Recipes.get_recipe(recipe.id, household.id)

    # 2 servings = need 2 cups, have 5 → :have
    availability = Recipes.check_availability(recipe, 2)
    [item] = availability
    assert item.status == :have
    assert Decimal.equal?(item.need, Decimal.new("2"))

    # 8 servings = need 8 cups, have 5 → :need
    availability = Recipes.check_availability(recipe, 8)
    [item] = availability
    assert item.status == :need
    assert Decimal.equal?(item.need, Decimal.new("8"))
  end

  test "marks unlinked ingredients as :untracked", %{recipe: recipe, household: household} do
    RecipesFixtures.ingredient_fixture(recipe, %{
      name: "Salt",
      quantity: Decimal.new("1")
    })

    recipe = Recipes.get_recipe(recipe.id, household.id)
    availability = Recipes.check_availability(recipe, 4)

    [item] = availability
    assert item.status == :untracked
    assert item.ingredient.name == "Salt"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/feed_me/recipes_test.exs --only describe:"check_availability"`

This won't match by describe. Instead run:

```bash
mix test test/feed_me/recipes_test.exs
```

Expected: compilation error — `Recipes.check_availability/2` is undefined.

**Step 3: Write minimal implementation**

Add to `lib/feed_me/recipes.ex` after `cook_recipe/3` (around line 310):

```elixir
@doc """
Returns ingredient availability for a recipe at a given serving count.

Each item in the returned list is a map with:
- `:ingredient` - the Ingredient struct
- `:have` - Decimal quantity in pantry (or nil if untracked)
- `:need` - Decimal quantity needed (scaled by servings)
- `:status` - `:have`, `:need`, or `:untracked`
"""
def check_availability(%Recipe{} = recipe, servings) do
  multiplier =
    if recipe.servings && recipe.servings > 0,
      do: Decimal.div(Decimal.new(servings), Decimal.new(recipe.servings)),
      else: Decimal.new(1)

  Enum.map(recipe.ingredients, fn ingredient ->
    needed =
      if ingredient.quantity,
        do: Decimal.mult(ingredient.quantity, multiplier),
        else: Decimal.new(1)

    cond do
      is_nil(ingredient.pantry_item_id) ->
        %{ingredient: ingredient, have: nil, need: needed, status: :untracked}

      true ->
        pantry_item = Pantry.get_item(ingredient.pantry_item_id)
        have = (pantry_item && pantry_item.quantity) || Decimal.new(0)

        status =
          if Decimal.compare(have, needed) != :lt, do: :have, else: :need

        %{ingredient: ingredient, have: have, need: needed, status: status}
    end
  end)
end
```

**Step 4: Run tests to verify they pass**

```bash
mix test test/feed_me/recipes_test.exs
```

Expected: all tests pass.

**Step 5: Commit**

```bash
git add lib/feed_me/recipes.ex test/feed_me/recipes_test.exs
git commit -m "Add Recipes.check_availability/2 for ingredient availability checks"
```

---

### Task 2: Wire availability into the cook modal

Update `apply_action(:cook, ...)` to precompute availability, add a servings change handler, and add the "add missing to list" event.

**Files:**
- Modify: `lib/feed_me_web/live/recipe_live/show.ex`

**Step 1: Update `apply_action` for `:cook`**

Change the existing `apply_action(socket, :cook, _params)` (around line 51) from:

```elixir
defp apply_action(socket, :cook, _params) do
  socket
  |> assign(:page_title, "Cook Recipe")
end
```

To:

```elixir
defp apply_action(socket, :cook, _params) do
  recipe = socket.assigns.recipe
  servings = recipe.servings || 1

  socket
  |> assign(:page_title, "Cook Recipe")
  |> assign(:cook_servings, servings)
  |> assign(:availability, Recipes.check_availability(recipe, servings))
end
```

**Step 2: Add servings change handler**

Add a new `handle_event` for servings changes:

```elixir
def handle_event("update_cook_servings", %{"servings" => servings_str}, socket) do
  servings = max(String.to_integer(servings_str), 1)
  availability = Recipes.check_availability(socket.assigns.recipe, servings)
  {:noreply, assign(socket, cook_servings: servings, availability: availability)}
end
```

**Step 3: Add "add missing to list" handler**

```elixir
def handle_event("add_missing_to_list", _params, socket) do
  user = socket.assigns.current_scope.user

  {:ok, %{added: added, already_have: have}} =
    Recipes.add_missing_to_list(socket.assigns.recipe, socket.assigns.household.id, user)

  message =
    cond do
      added == 0 && have > 0 -> "You already have all the ingredients!"
      added > 0 && have > 0 -> "Added #{added} items to shopping list (you have #{have})"
      added > 0 -> "Added #{added} items to shopping list"
      true -> "No ingredients to add"
    end

  # Recompute availability after adding to list
  availability = Recipes.check_availability(socket.assigns.recipe, socket.assigns.cook_servings)

  {:noreply,
   socket
   |> assign(:availability, availability)
   |> put_flash(:info, message)}
end
```

**Step 4: Verify it compiles**

```bash
mix compile --warnings-as-errors
```

Expected: no errors.

**Step 5: Commit**

```bash
git add lib/feed_me_web/live/recipe_live/show.ex
git commit -m "Wire ingredient availability into cook modal"
```

---

### Task 3: Redesign the cook modal template

Replace the existing cook modal with the new design showing ingredient availability, two action buttons, and the updated button label.

**Files:**
- Modify: `lib/feed_me_web/live/recipe_live/show.ex` (template section)

**Step 1: Change "Cook It" button label**

Find the current button (around line 322-324):

```heex
<.link patch={~p"/households/#{@household.id}/recipes/#{@recipe.id}/cook"}>
  <.button>Cook It</.button>
</.link>
```

Replace with:

```heex
<.link patch={~p"/households/#{@household.id}/recipes/#{@recipe.id}/cook"}>
  <.button>I Cooked This</.button>
</.link>
```

**Step 2: Replace the cook modal**

Find the existing cook modal (starts around line 546 with `<.modal :if={@live_action == :cook}`). Replace the entire modal block with:

```heex
<.modal
  :if={@live_action == :cook}
  id="cook-recipe-modal"
  show
  on_cancel={JS.patch(~p"/households/#{@household.id}/recipes/#{@recipe.id}")}
>
  <.header>
    I Cooked {@recipe.title}
    <:subtitle>Update your pantry inventory</:subtitle>
  </.header>

  <div class="mt-4">
    <label class="label" for="cook-servings">Servings made</label>
    <input
      id="cook-servings"
      name="servings"
      type="number"
      value={@cook_servings}
      min="1"
      phx-change="update_cook_servings"
      class="input input-bordered w-full"
    />
  </div>

  <%!-- Ingredient availability --%>
  <% have_items = Enum.filter(@availability, &(&1.status == :have)) %>
  <% need_items = Enum.filter(@availability, &(&1.status == :need)) %>
  <% untracked_items = Enum.filter(@availability, &(&1.status == :untracked)) %>

  <%= if need_items != [] do %>
    <div class="mt-4">
      <h4 class="text-sm font-semibold text-warning mb-2">
        Need ({length(need_items)})
      </h4>
      <ul class="space-y-1">
        <%= for item <- need_items do %>
          <li class="flex justify-between text-sm py-1 px-2 bg-warning/10 rounded">
            <span>{item.ingredient.name}</span>
            <span class="text-warning">
              have {Decimal.round(item.have, 1)}, need {Decimal.round(item.need, 1)}
              {item.ingredient.unit}
            </span>
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <%= if have_items != [] do %>
    <div class="mt-4">
      <h4 class="text-sm font-semibold text-success mb-2">
        Ready ({length(have_items)})
      </h4>
      <ul class="space-y-1">
        <%= for item <- have_items do %>
          <li class="flex justify-between text-sm py-1 px-2 bg-success/10 rounded">
            <span>{item.ingredient.name}</span>
            <span class="text-success">
              {Decimal.round(item.have, 1)} / {Decimal.round(item.need, 1)}
              {item.ingredient.unit}
            </span>
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <%= if untracked_items != [] do %>
    <div class="mt-4">
      <h4 class="text-sm font-semibold text-base-content/50 mb-2">
        Not tracked ({length(untracked_items)})
      </h4>
      <ul class="space-y-1">
        <%= for item <- untracked_items do %>
          <li class="text-sm py-1 px-2 text-base-content/50">
            {item.ingredient.name}
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <form phx-submit="cook_confirmed" class="mt-6 space-y-4">
    <input type="hidden" name="servings" value={@cook_servings} />
    <.input
      name="rating"
      type="select"
      label="Rating"
      prompt="Rate this meal..."
      options={[
        {"1 star", "1"},
        {"2 stars", "2"},
        {"3 stars", "3"},
        {"4 stars", "4"},
        {"5 stars", "5"}
      ]}
    />
    <.input
      name="notes"
      type="textarea"
      label="Notes (optional)"
      placeholder="How did it turn out?"
    />
    <div class="flex gap-2 justify-end">
      <%= if need_items != [] do %>
        <button
          type="button"
          phx-click="add_missing_to_list"
          class="btn btn-outline btn-warning"
        >
          Add Missing to List
        </button>
      <% end %>
      <.button type="submit" variant="primary">
        Cooked It!
      </.button>
    </div>
  </form>
</.modal>
```

**Step 3: Verify it compiles and the full test suite still passes**

```bash
mix compile --warnings-as-errors && mix test
```

Expected: 314 tests, 1 failure (pre-existing).

**Step 4: Commit**

```bash
git add lib/feed_me_web/live/recipe_live/show.ex
git commit -m "Redesign cook modal with ingredient availability and add-to-list"
```

---

### Task 4: Manual testing and edge cases

Verify the flow works end-to-end and handle edge cases.

**Step 1: Test locally**

Start the dev server: `iex -S mix phx.server`

1. Navigate to a recipe with linked pantry ingredients
2. Click "I Cooked This" — verify modal shows availability grouped correctly
3. Change servings — verify availability updates
4. Click "Add Missing to List" if items are missing — verify flash and list update
5. Submit "Cooked It!" — verify pantry decrements and cooking log created
6. Test a recipe with NO ingredients — verify modal still works (empty lists)
7. Test a recipe with unlinked ingredients — verify "Not tracked" section appears

**Step 2: Fix any issues found**

Address any compilation warnings or UI glitches.

**Step 3: Final commit if needed**

```bash
git add -A
git commit -m "Polish cook dialog edge cases"
```
