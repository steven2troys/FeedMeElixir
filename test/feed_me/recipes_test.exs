defmodule FeedMe.RecipesTest do
  use FeedMe.DataCase

  alias FeedMe.Recipes
  alias FeedMe.Recipes.{Recipe, Ingredient, Photo, CookingLog}
  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures
  alias FeedMe.PantryFixtures
  alias FeedMe.RecipesFixtures

  describe "recipes" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "list_recipes/1 returns all recipes for a household", %{household: household} do
      recipe = RecipesFixtures.recipe_fixture(household)
      recipes = Recipes.list_recipes(household.id)
      assert length(recipes) == 1
      assert hd(recipes).id == recipe.id
    end

    test "list_recipes/2 filters by favorite", %{household: household} do
      _recipe1 = RecipesFixtures.recipe_fixture(household, %{title: "Regular"})
      recipe2 = RecipesFixtures.recipe_fixture(household, %{title: "Favorite", is_favorite: true})

      favorites = Recipes.list_recipes(household.id, favorites_only: true)
      assert length(favorites) == 1
      assert hd(favorites).id == recipe2.id
    end

    test "search_recipes/2 filters by search term", %{household: household} do
      recipe1 = RecipesFixtures.recipe_fixture(household, %{title: "Chicken Curry"})
      _recipe2 = RecipesFixtures.recipe_fixture(household, %{title: "Beef Stew"})

      results = Recipes.search_recipes(household.id, "chicken")
      assert length(results) == 1
      assert hd(results).id == recipe1.id
    end

    test "list_recipes/2 filters by tag", %{household: household} do
      recipe1 =
        RecipesFixtures.recipe_fixture(household, %{title: "Quick Meal", tags: ["quick", "easy"]})

      _recipe2 =
        RecipesFixtures.recipe_fixture(household, %{title: "Slow Cook", tags: ["slow", "weekend"]})

      results = Recipes.list_recipes(household.id, tag: "quick")
      assert length(results) == 1
      assert hd(results).id == recipe1.id
    end

    test "get_recipe/2 returns recipe with preloads", %{household: household} do
      recipe = RecipesFixtures.recipe_fixture(household)
      RecipesFixtures.ingredient_fixture(recipe)
      RecipesFixtures.photo_fixture(recipe)

      fetched = Recipes.get_recipe(recipe.id, household.id)
      assert fetched.id == recipe.id
      assert length(fetched.ingredients) == 1
      assert length(fetched.photos) == 1
    end

    test "get_recipe/2 returns nil for wrong household", %{household: household} do
      recipe = RecipesFixtures.recipe_fixture(household)
      other_user = AccountsFixtures.user_fixture()
      other_household = HouseholdsFixtures.household_fixture(%{}, other_user)

      assert Recipes.get_recipe(recipe.id, other_household.id) == nil
    end

    test "create_recipe/1 creates a recipe", %{household: household} do
      attrs = %{title: "New Recipe", servings: 2, household_id: household.id}
      assert {:ok, %Recipe{} = recipe} = Recipes.create_recipe(attrs)
      assert recipe.title == "New Recipe"
      assert recipe.servings == 2
      assert recipe.household_id == household.id
    end

    test "update_recipe/2 updates a recipe", %{household: household} do
      recipe = RecipesFixtures.recipe_fixture(household)
      assert {:ok, %Recipe{} = updated} = Recipes.update_recipe(recipe, %{title: "Updated Title"})
      assert updated.title == "Updated Title"
    end

    test "delete_recipe/1 deletes a recipe", %{household: household} do
      recipe = RecipesFixtures.recipe_fixture(household)
      assert {:ok, %Recipe{}} = Recipes.delete_recipe(recipe)
      assert Recipes.get_recipe(recipe.id, household.id) == nil
    end

    test "toggle_favorite/1 toggles favorite status", %{household: household} do
      recipe = RecipesFixtures.recipe_fixture(household, %{is_favorite: false})
      assert recipe.is_favorite == false

      {:ok, favorited} = Recipes.toggle_favorite(recipe)
      assert favorited.is_favorite == true

      {:ok, unfavorited} = Recipes.toggle_favorite(favorited)
      assert unfavorited.is_favorite == false
    end

    test "list_tags/1 returns unique tags", %{household: household} do
      RecipesFixtures.recipe_fixture(household, %{tags: ["dinner", "easy"]})
      RecipesFixtures.recipe_fixture(household, %{tags: ["lunch", "easy"]})

      tags = Recipes.list_tags(household.id)
      assert "dinner" in tags
      assert "lunch" in tags
      assert "easy" in tags
      assert length(tags) == 3
    end
  end

  describe "ingredients" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      recipe = RecipesFixtures.recipe_fixture(household)
      %{user: user, household: household, recipe: recipe}
    end

    test "create_ingredient/1 adds an ingredient to recipe", %{recipe: recipe} do
      attrs = %{name: "Flour", quantity: Decimal.new("2"), unit: "cups", recipe_id: recipe.id}
      assert {:ok, %Ingredient{} = ingredient} = Recipes.create_ingredient(attrs)
      assert ingredient.name == "Flour"
      assert ingredient.recipe_id == recipe.id
    end

    test "create_ingredient/1 links to pantry item", %{recipe: recipe, household: household} do
      pantry_item = PantryFixtures.item_fixture(household, %{name: "Sugar"})
      attrs = %{name: "Sugar", pantry_item_id: pantry_item.id, recipe_id: recipe.id}

      assert {:ok, %Ingredient{} = ingredient} = Recipes.create_ingredient(attrs)
      assert ingredient.pantry_item_id == pantry_item.id
    end

    test "update_ingredient/2 updates an ingredient", %{recipe: recipe} do
      ingredient = RecipesFixtures.ingredient_fixture(recipe)

      assert {:ok, %Ingredient{} = updated} =
               Recipes.update_ingredient(ingredient, %{name: "Updated"})

      assert updated.name == "Updated"
    end

    test "delete_ingredient/1 deletes an ingredient", %{recipe: recipe} do
      ingredient = RecipesFixtures.ingredient_fixture(recipe)
      assert {:ok, %Ingredient{}} = Recipes.delete_ingredient(ingredient)

      fetched = Recipes.get_recipe(recipe.id, recipe.household_id)
      assert fetched.ingredients == []
    end
  end

  describe "photos" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      recipe = RecipesFixtures.recipe_fixture(household)
      %{user: user, household: household, recipe: recipe}
    end

    test "create_photo/1 adds a photo to recipe", %{recipe: recipe} do
      attrs = %{
        url: "https://example.com/photo.jpg",
        caption: "Finished dish",
        recipe_id: recipe.id
      }

      assert {:ok, %Photo{} = photo} = Recipes.create_photo(attrs)
      assert photo.url == "https://example.com/photo.jpg"
      assert photo.recipe_id == recipe.id
    end

    test "delete_photo/1 deletes a photo", %{recipe: recipe} do
      photo = RecipesFixtures.photo_fixture(recipe)
      assert {:ok, %Photo{}} = Recipes.delete_photo(photo)

      fetched = Recipes.get_recipe(recipe.id, recipe.household_id)
      assert fetched.photos == []
    end
  end

  describe "cooking" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      recipe = RecipesFixtures.recipe_fixture(household, %{servings: 4})
      %{user: user, household: household, recipe: recipe}
    end

    test "cook_recipe/3 creates a cooking log", %{
      recipe: recipe,
      household: household,
      user: user
    } do
      assert {:ok, %CookingLog{} = log} = Recipes.cook_recipe(recipe, user, servings_made: 4)
      assert log.recipe_id == recipe.id
      assert log.household_id == household.id
      assert log.cooked_by_id == user.id
      assert log.servings_made == 4
    end

    test "cook_recipe/3 with rating and notes", %{recipe: recipe, user: user} do
      opts = [servings_made: 2, rating: 5, notes: "Delicious!"]
      assert {:ok, %CookingLog{} = log} = Recipes.cook_recipe(recipe, user, opts)
      assert log.rating == 5
      assert log.notes == "Delicious!"
    end

    test "cook_recipe/3 decrements pantry items", %{
      recipe: recipe,
      household: household,
      user: user
    } do
      # Create pantry item with quantity
      pantry_item =
        PantryFixtures.item_fixture(household, %{name: "Chicken", quantity: Decimal.new("10")})

      # Add ingredient linked to pantry item (2 units per serving, recipe serves 4)
      RecipesFixtures.ingredient_fixture(recipe, %{
        name: "Chicken",
        pantry_item_id: pantry_item.id,
        quantity: Decimal.new("2")
      })

      # Reload recipe with ingredients
      recipe = Recipes.get_recipe(recipe.id, household.id)

      # Cook the recipe (4 servings)
      {:ok, _log} = Recipes.cook_recipe(recipe, user, servings_made: 4)

      # Check pantry was decremented: 10 - 2 = 8
      updated_pantry = FeedMe.Pantry.get_item(pantry_item.id, household.id)
      assert Decimal.equal?(updated_pantry.quantity, Decimal.new("8"))
    end

    test "cook_recipe/3 scales ingredient amounts", %{
      recipe: recipe,
      household: household,
      user: user
    } do
      # Recipe serves 4, we'll cook 2 servings (half)
      pantry_item =
        PantryFixtures.item_fixture(household, %{name: "Rice", quantity: Decimal.new("10")})

      # 4 cups for 4 servings = 1 cup per serving
      RecipesFixtures.ingredient_fixture(recipe, %{
        name: "Rice",
        pantry_item_id: pantry_item.id,
        quantity: Decimal.new("4")
      })

      recipe = Recipes.get_recipe(recipe.id, household.id)

      # Cook 2 servings (half of 4)
      {:ok, _log} = Recipes.cook_recipe(recipe, user, servings_made: 2)

      # Should deduct 2 cups (half of 4): 10 - 2 = 8
      updated_pantry = FeedMe.Pantry.get_item(pantry_item.id, household.id)
      assert Decimal.equal?(updated_pantry.quantity, Decimal.new("8"))
    end

    test "list_cooking_logs/2 returns recent logs", %{
      recipe: recipe,
      household: household,
      user: user
    } do
      {:ok, _log1} = Recipes.cook_recipe(recipe, user, servings_made: 2)
      {:ok, _log2} = Recipes.cook_recipe(recipe, user, servings_made: 4)

      history = Recipes.list_cooking_logs(household.id, limit: 10)
      assert length(history) == 2
    end
  end

  describe "add_missing_to_list" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      recipe = RecipesFixtures.recipe_fixture(household)
      %{user: user, household: household, recipe: recipe}
    end

    test "adds missing ingredients to shopping list", %{
      recipe: recipe,
      household: household,
      user: user
    } do
      # Add ingredient not in pantry
      RecipesFixtures.ingredient_fixture(recipe, %{name: "Onions", quantity: Decimal.new("2")})
      recipe = Recipes.get_recipe(recipe.id, household.id)

      {:ok, %{added: added, already_have: have}} =
        Recipes.add_missing_to_list(recipe, household.id, user)

      assert added == 1
      assert have == 0

      # Verify item is in shopping list
      list = FeedMe.Shopping.get_or_create_main_list(household.id)
      items = FeedMe.Shopping.list_items(list.id)
      assert length(items) == 1
      assert hd(items).name == "Onions"
    end

    test "skips ingredients already in pantry", %{
      recipe: recipe,
      household: household,
      user: user
    } do
      # Create pantry item with sufficient quantity
      pantry_item =
        PantryFixtures.item_fixture(household, %{name: "Salt", quantity: Decimal.new("10")})

      # Add ingredient linked to pantry item
      RecipesFixtures.ingredient_fixture(recipe, %{
        name: "Salt",
        pantry_item_id: pantry_item.id,
        quantity: Decimal.new("1")
      })

      recipe = Recipes.get_recipe(recipe.id, household.id)

      {:ok, %{added: added, already_have: have}} =
        Recipes.add_missing_to_list(recipe, household.id, user)

      assert added == 0
      assert have == 1
    end

    test "adds items with insufficient pantry quantity", %{
      recipe: recipe,
      household: household,
      user: user
    } do
      # Create pantry item with less than needed
      pantry_item =
        PantryFixtures.item_fixture(household, %{name: "Butter", quantity: Decimal.new("1")})

      # Recipe needs 3 but we only have 1
      RecipesFixtures.ingredient_fixture(recipe, %{
        name: "Butter",
        pantry_item_id: pantry_item.id,
        quantity: Decimal.new("3")
      })

      recipe = Recipes.get_recipe(recipe.id, household.id)

      {:ok, %{added: added, already_have: have}} =
        Recipes.add_missing_to_list(recipe, household.id, user)

      assert added == 1
      assert have == 0
    end
  end
end
