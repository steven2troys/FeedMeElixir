defmodule FeedMe.MealPlanning do
  @moduledoc """
  The MealPlanning context manages meal plans and their items.
  """

  import Ecto.Query, warn: false
  alias FeedMe.Repo
  alias FeedMe.MealPlanning.{MealPlan, MealPlanItem}
  alias FeedMe.{Pantry, Shopping}

  # =============================================================================
  # PubSub
  # =============================================================================

  @doc """
  Subscribes to meal planning updates for a household.
  """
  def subscribe(household_id) do
    Phoenix.PubSub.subscribe(FeedMe.PubSub, topic(household_id))
  end

  defp topic(household_id), do: "meal_planning:#{household_id}"

  defp broadcast(household_id, event) do
    Phoenix.PubSub.broadcast(FeedMe.PubSub, topic(household_id), event)
  end

  # =============================================================================
  # Meal Plans
  # =============================================================================

  @doc """
  Lists meal plans for a household.
  """
  def list_meal_plans(household_id, opts \\ []) do
    query =
      MealPlan
      |> where([mp], mp.household_id == ^household_id)
      |> order_by([mp], desc: mp.start_date)

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [mp], mp.status == ^status)
      end

    Repo.all(query)
  end

  @doc """
  Gets a meal plan by ID, scoped to a household.
  """
  def get_meal_plan(id, household_id) do
    MealPlan
    |> where([mp], mp.id == ^id and mp.household_id == ^household_id)
    |> Repo.one()
  end

  @doc """
  Gets a meal plan with items preloaded.
  """
  def get_meal_plan_with_items(id, household_id) do
    MealPlan
    |> where([mp], mp.id == ^id and mp.household_id == ^household_id)
    |> preload(items: :recipe)
    |> Repo.one()
  end

  @doc """
  Creates a meal plan.
  """
  def create_meal_plan(attrs) do
    result =
      %MealPlan{}
      |> MealPlan.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, meal_plan} ->
        broadcast(meal_plan.household_id, {:meal_plan_created, meal_plan})
        {:ok, meal_plan}

      error ->
        error
    end
  end

  @doc """
  Updates a meal plan.
  """
  def update_meal_plan(%MealPlan{} = meal_plan, attrs) do
    result =
      meal_plan
      |> MealPlan.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, meal_plan} ->
        broadcast(meal_plan.household_id, {:meal_plan_updated, meal_plan})
        {:ok, meal_plan}

      error ->
        error
    end
  end

  @doc """
  Deletes a meal plan.
  """
  def delete_meal_plan(%MealPlan{} = meal_plan) do
    result = Repo.delete(meal_plan)

    case result do
      {:ok, meal_plan} ->
        broadcast(meal_plan.household_id, {:meal_plan_deleted, meal_plan})
        {:ok, meal_plan}

      error ->
        error
    end
  end

  @doc """
  Returns a changeset for a meal plan.
  """
  def change_meal_plan(%MealPlan{} = meal_plan, attrs \\ %{}) do
    MealPlan.changeset(meal_plan, attrs)
  end

  # =============================================================================
  # Meal Plan Items
  # =============================================================================

  @doc """
  Lists items for a meal plan.
  """
  def list_items(meal_plan_id) do
    MealPlanItem
    |> where([i], i.meal_plan_id == ^meal_plan_id)
    |> order_by([i], asc: i.date, asc: i.sort_order)
    |> preload(:recipe)
    |> Repo.all()
  end

  @doc """
  Gets a meal plan item by ID.
  """
  def get_item(id) do
    MealPlanItem
    |> preload(:recipe)
    |> Repo.get(id)
  end

  @doc """
  Creates a meal plan item.
  """
  def create_item(attrs) do
    result =
      %MealPlanItem{}
      |> MealPlanItem.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, item} ->
        meal_plan = Repo.get(MealPlan, item.meal_plan_id)

        if meal_plan do
          broadcast(meal_plan.household_id, {:meal_plan_item_added, item})
        end

        {:ok, Repo.preload(item, :recipe)}

      error ->
        error
    end
  end

  @doc """
  Updates a meal plan item.
  """
  def update_item(%MealPlanItem{} = item, attrs) do
    result =
      item
      |> MealPlanItem.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, item} ->
        meal_plan = Repo.get(MealPlan, item.meal_plan_id)

        if meal_plan do
          broadcast(meal_plan.household_id, {:meal_plan_item_updated, item})
        end

        {:ok, Repo.preload(item, :recipe)}

      error ->
        error
    end
  end

  @doc """
  Deletes a meal plan item.
  """
  def delete_item(%MealPlanItem{} = item) do
    meal_plan = Repo.get(MealPlan, item.meal_plan_id)
    result = Repo.delete(item)

    case result do
      {:ok, item} ->
        if meal_plan do
          broadcast(meal_plan.household_id, {:meal_plan_item_deleted, item})
        end

        {:ok, item}

      error ->
        error
    end
  end

  @doc """
  Returns a changeset for a meal plan item.
  """
  def change_item(%MealPlanItem{} = item, attrs \\ %{}) do
    MealPlanItem.changeset(item, attrs)
  end

  # =============================================================================
  # Shopping Needs Calculation
  # =============================================================================

  @doc """
  Calculates shopping needs for a meal plan by aggregating ingredient needs
  across all recipes and subtracting pantry stock.

  Returns a list of maps with :name, :quantity, :unit, :have, :need, :pantry_item_id.
  """
  def calculate_shopping_needs(%MealPlan{} = meal_plan) do
    meal_plan = Repo.preload(meal_plan, items: [recipe: [ingredients: :pantry_item]])

    # Aggregate ingredient needs across all recipe items
    ingredient_needs =
      meal_plan.items
      |> Enum.filter(& &1.recipe)
      |> Enum.flat_map(fn item ->
        servings_multiplier = calculate_servings_multiplier(item)

        Enum.map(item.recipe.ingredients, fn ingredient ->
          base_qty = ingredient.quantity || Decimal.new(1)
          needed_qty = Decimal.mult(base_qty, servings_multiplier)

          %{
            name: ingredient.name,
            quantity: needed_qty,
            unit: ingredient.unit,
            pantry_item_id: ingredient.pantry_item_id
          }
        end)
      end)

    # Group by ingredient name and sum quantities
    grouped =
      ingredient_needs
      |> Enum.group_by(fn i -> {String.downcase(i.name), i.unit} end)
      |> Enum.map(fn {{_name, unit}, items} ->
        total_needed = Enum.reduce(items, Decimal.new(0), &Decimal.add(&2, &1.quantity))
        first = hd(items)
        pantry_item_id = Enum.find_value(items, & &1.pantry_item_id)

        # Check pantry stock
        have =
          if pantry_item_id do
            pantry_item = Pantry.get_item(pantry_item_id)
            (pantry_item && pantry_item.quantity) || Decimal.new(0)
          else
            Decimal.new(0)
          end

        still_need = Decimal.max(Decimal.sub(total_needed, have), Decimal.new(0))

        %{
          name: first.name,
          quantity: total_needed,
          unit: unit,
          have: have,
          need: still_need,
          pantry_item_id: pantry_item_id
        }
      end)
      |> Enum.filter(fn item -> Decimal.compare(item.need, Decimal.new(0)) == :gt end)
      |> Enum.sort_by(& &1.name)

    grouped
  end

  @doc """
  Adds calculated shopping needs to the main shopping list.
  """
  def add_needs_to_shopping_list(%MealPlan{} = meal_plan, user) do
    needs = calculate_shopping_needs(meal_plan)
    main_list = Shopping.get_or_create_main_list(meal_plan.household_id)

    # Get existing shopping list items to avoid duplicates
    existing_in_list =
      Shopping.list_items(main_list.id)
      |> Enum.filter(& &1.pantry_item_id)
      |> Enum.map(& &1.pantry_item_id)
      |> MapSet.new()

    added =
      Enum.reduce(needs, 0, fn item, count ->
        # Skip if already in shopping list
        if item.pantry_item_id && MapSet.member?(existing_in_list, item.pantry_item_id) do
          count
        else
          attrs = %{
            name: item.name,
            quantity: item.need,
            unit: item.unit,
            shopping_list_id: main_list.id,
            pantry_item_id: item.pantry_item_id,
            added_by_id: user.id
          }

          case Shopping.create_item(attrs) do
            {:ok, _} -> count + 1
            _ -> count
          end
        end
      end)

    {:ok, %{added: added, total_needs: length(needs)}}
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp calculate_servings_multiplier(%MealPlanItem{servings: nil}), do: Decimal.new(1)

  defp calculate_servings_multiplier(%MealPlanItem{servings: item_servings, recipe: recipe})
       when not is_nil(recipe) do
    recipe_servings = recipe.servings || 1

    if recipe_servings > 0 do
      Decimal.div(Decimal.new(item_servings), Decimal.new(recipe_servings))
    else
      Decimal.new(1)
    end
  end

  defp calculate_servings_multiplier(_), do: Decimal.new(1)

  @doc """
  Returns a list of dates between start_date and end_date (inclusive).
  """
  def date_range(%MealPlan{start_date: start_date, end_date: end_date}) do
    Date.range(start_date, end_date)
    |> Enum.to_list()
  end
end
