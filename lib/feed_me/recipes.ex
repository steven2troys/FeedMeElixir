defmodule FeedMe.Recipes do
  @moduledoc """
  The Recipes context manages recipes, ingredients, and cooking history.
  """

  import Ecto.Query, warn: false
  alias FeedMe.Pantry
  alias FeedMe.Recipes.{CookingLog, Ingredient, Photo, Recipe}
  alias FeedMe.Repo
  alias FeedMe.Shopping

  # =============================================================================
  # Recipes
  # =============================================================================

  @doc """
  Lists all recipes for a household.
  """
  def list_recipes(household_id, opts \\ []) do
    query =
      Recipe
      |> where([r], r.household_id == ^household_id)
      |> preload([:photos, :ingredients])

    query =
      case Keyword.get(opts, :favorites_only) do
        true -> where(query, [r], r.is_favorite == true)
        _ -> query
      end

    query =
      case Keyword.get(opts, :tag) do
        nil -> query
        tag -> where(query, [r], ^tag in r.tags)
      end

    query =
      case Keyword.get(opts, :order_by) do
        :title -> order_by(query, [r], asc: r.title)
        :newest -> order_by(query, [r], desc: r.inserted_at)
        :total_time -> order_by(query, [r], asc: coalesce(r.prep_time_minutes, 0) + coalesce(r.cook_time_minutes, 0))
        _ -> order_by(query, [r], asc: r.title)
      end

    Repo.all(query)
  end

  @doc """
  Searches recipes by title or tags.
  """
  def search_recipes(household_id, query) do
    search_term = "%#{query}%"

    Recipe
    |> where([r], r.household_id == ^household_id)
    |> where([r], ilike(r.title, ^search_term) or ilike(r.description, ^search_term))
    |> preload([:photos, :ingredients])
    |> order_by([r], asc: r.title)
    |> Repo.all()
  end

  @doc """
  Gets a recipe by ID.
  """
  def get_recipe(id) do
    Recipe
    |> Repo.get(id)
    |> Repo.preload([:photos, :ingredients, :cooking_logs])
  end

  @doc """
  Gets a recipe by ID, ensuring it belongs to the household.
  """
  def get_recipe(id, household_id) do
    Recipe
    |> where([r], r.id == ^id and r.household_id == ^household_id)
    |> preload([:photos, ingredients: :pantry_item, cooking_logs: :cooked_by])
    |> Repo.one()
  end

  @doc """
  Creates a recipe.
  """
  def create_recipe(attrs) do
    %Recipe{}
    |> Recipe.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a recipe.
  """
  def update_recipe(%Recipe{} = recipe, attrs) do
    recipe
    |> Recipe.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a recipe.
  """
  def delete_recipe(%Recipe{} = recipe) do
    Repo.delete(recipe)
  end

  @doc """
  Toggles a recipe's favorite status.
  """
  def toggle_favorite(%Recipe{} = recipe) do
    update_recipe(recipe, %{is_favorite: !recipe.is_favorite})
  end

  @doc """
  Returns a changeset for tracking recipe changes.
  """
  def change_recipe(%Recipe{} = recipe, attrs \\ %{}) do
    Recipe.changeset(recipe, attrs)
  end

  # =============================================================================
  # Ingredients
  # =============================================================================

  @doc """
  Gets an ingredient by ID.
  """
  def get_ingredient(id), do: Repo.get(Ingredient, id)

  @doc """
  Creates an ingredient.
  """
  def create_ingredient(attrs) do
    %Ingredient{}
    |> Ingredient.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an ingredient.
  """
  def update_ingredient(%Ingredient{} = ingredient, attrs) do
    ingredient
    |> Ingredient.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an ingredient.
  """
  def delete_ingredient(%Ingredient{} = ingredient) do
    Repo.delete(ingredient)
  end

  @doc """
  Bulk creates ingredients for a recipe.
  """
  def bulk_create_ingredients(recipe_id, ingredient_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    ingredients =
      ingredient_list
      |> Enum.with_index()
      |> Enum.map(fn {attrs, index} ->
        %{
          id: Ecto.UUID.generate(),
          name: attrs.name,
          quantity: attrs[:quantity],
          unit: attrs[:unit],
          notes: attrs[:notes],
          optional: attrs[:optional] || false,
          sort_order: index,
          recipe_id: recipe_id,
          pantry_item_id: attrs[:pantry_item_id],
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Ingredient, ingredients)
  end

  # =============================================================================
  # Photos
  # =============================================================================

  @doc """
  Creates a photo.
  """
  def create_photo(attrs) do
    %Photo{}
    |> Photo.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a photo.
  """
  def delete_photo(%Photo{} = photo) do
    Repo.delete(photo)
  end

  # =============================================================================
  # Cook Recipe
  # =============================================================================

  @doc """
  Cooks a recipe - decrements pantry quantities and creates a log.

  Options:
  - :servings_made - number of servings (defaults to recipe servings)
  - :notes - cooking notes
  - :rating - 1-5 star rating
  """
  def cook_recipe(%Recipe{} = recipe, user, opts \\ []) do
    servings_made = Keyword.get(opts, :servings_made) || recipe.servings || 1
    multiplier = if recipe.servings, do: Decimal.div(Decimal.new(servings_made), Decimal.new(recipe.servings)), else: Decimal.new(1)

    recipe = Repo.preload(recipe, ingredients: :pantry_item)

    Repo.transaction(fn ->
      # Decrement pantry items
      Enum.each(recipe.ingredients, fn ingredient ->
        if ingredient.pantry_item_id && ingredient.quantity do
          pantry_item = Pantry.get_item(ingredient.pantry_item_id)

          if pantry_item do
            quantity_to_use = Decimal.mult(ingredient.quantity, multiplier)

            Pantry.use_item(pantry_item, quantity_to_use, user, reason: "Cooked #{recipe.title}")
          end
        end
      end)

      # Create cooking log
      {:ok, log} =
        create_cooking_log(%{
          recipe_id: recipe.id,
          household_id: recipe.household_id,
          cooked_by_id: user.id,
          servings_made: servings_made,
          notes: Keyword.get(opts, :notes),
          rating: Keyword.get(opts, :rating)
        })

      log
    end)
  end

  @doc """
  Creates a cooking log.
  """
  def create_cooking_log(attrs) do
    %CookingLog{}
    |> CookingLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists cooking logs for a household.
  """
  def list_cooking_logs(household_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    CookingLog
    |> where([c], c.household_id == ^household_id)
    |> order_by([c], desc: c.inserted_at)
    |> limit(^limit)
    |> preload([:recipe, :cooked_by])
    |> Repo.all()
  end

  @doc """
  Lists cooking logs for a recipe.
  """
  def list_cooking_logs_for_recipe(recipe_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    CookingLog
    |> where([c], c.recipe_id == ^recipe_id)
    |> order_by([c], desc: c.inserted_at)
    |> limit(^limit)
    |> preload(:cooked_by)
    |> Repo.all()
  end

  # =============================================================================
  # Add to Shopping List
  # =============================================================================

  @doc """
  Adds missing ingredients to the shopping list.

  Returns a map with :added and :already_have counts.
  """
  def add_missing_to_list(%Recipe{} = recipe, household_id, user) do
    recipe = Repo.preload(recipe, ingredients: :pantry_item)
    main_list = Shopping.get_or_create_main_list(household_id)

    # Get current pantry quantities
    pantry_quantities =
      recipe.ingredients
      |> Enum.filter(& &1.pantry_item_id)
      |> Enum.map(fn ing ->
        pantry_item = Pantry.get_item(ing.pantry_item_id)
        {ing.id, pantry_item && pantry_item.quantity || Decimal.new(0)}
      end)
      |> Map.new()

    # Check what's already in the shopping list
    existing_in_list =
      Shopping.list_items(main_list.id)
      |> Enum.filter(& &1.pantry_item_id)
      |> Enum.map(& &1.pantry_item_id)
      |> MapSet.new()

    results =
      Enum.reduce(recipe.ingredients, %{added: 0, already_have: 0}, fn ingredient, acc ->
        needed = ingredient.quantity || Decimal.new(1)
        have = pantry_quantities[ingredient.id] || Decimal.new(0)

        cond do
          # Already have enough
          Decimal.compare(have, needed) != :lt ->
            %{acc | already_have: acc.already_have + 1}

          # Already in shopping list
          ingredient.pantry_item_id && MapSet.member?(existing_in_list, ingredient.pantry_item_id) ->
            acc

          # Need to add
          true ->
            quantity_needed = Decimal.sub(needed, have)

            attrs = %{
              name: ingredient.name,
              quantity: quantity_needed,
              unit: ingredient.unit,
              shopping_list_id: main_list.id,
              pantry_item_id: ingredient.pantry_item_id,
              added_by_id: user.id
            }

            Shopping.create_item(attrs)
            %{acc | added: acc.added + 1}
        end
      end)

    {:ok, results}
  end

  @doc """
  Gets all unique tags used in a household's recipes.
  """
  def list_tags(household_id) do
    Recipe
    |> where([r], r.household_id == ^household_id)
    |> select([r], r.tags)
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end
end
