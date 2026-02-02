defmodule FeedMe.RecipesFixtures do
  @moduledoc """
  Test fixtures for Recipes context.
  """

  alias FeedMe.Recipes

  def recipe_fixture(household, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        title: "Test Recipe #{System.unique_integer([:positive])}",
        description: "A delicious test recipe",
        instructions: "Step 1: Mix ingredients\nStep 2: Cook\nStep 3: Serve",
        servings: 4,
        prep_time_minutes: 15,
        cook_time_minutes: 30,
        tags: ["dinner", "easy"]
      })
      |> Map.put(:household_id, household.id)

    {:ok, recipe} = Recipes.create_recipe(attrs)
    recipe
  end

  def ingredient_fixture(recipe, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        name: "Test Ingredient #{System.unique_integer([:positive])}",
        quantity: Decimal.new("1"),
        unit: "cup",
        sort_order: 0
      })
      |> Map.put(:recipe_id, recipe.id)

    {:ok, ingredient} = Recipes.create_ingredient(attrs)
    ingredient
  end

  def photo_fixture(recipe, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        url: "https://example.com/photo#{System.unique_integer([:positive])}.jpg",
        caption: "Test photo",
        sort_order: 0
      })
      |> Map.put(:recipe_id, recipe.id)

    {:ok, photo} = Recipes.create_photo(attrs)
    photo
  end
end
