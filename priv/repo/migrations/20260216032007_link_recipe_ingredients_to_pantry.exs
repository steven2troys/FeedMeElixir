defmodule FeedMe.Repo.Migrations.LinkRecipeIngredientsToPantry do
  use Ecto.Migration

  import Ecto.Query

  def up do
    # Get all recipes with their household_id
    recipes =
      from(r in "recipes", select: %{id: r.id, household_id: r.household_id})
      |> repo().all()

    for recipe <- recipes do
      # Get unlinked ingredients for this recipe
      ingredients =
        from(i in "recipe_ingredients",
          where: i.recipe_id == ^recipe.id and is_nil(i.pantry_item_id),
          select: %{id: i.id, name: i.name, unit: i.unit}
        )
        |> repo().all()

      # Get the "Pantry" storage location for this household
      location =
        from(l in "storage_locations",
          where: l.household_id == ^recipe.household_id and l.name == "Pantry" and l.is_default == false,
          select: %{id: l.id},
          limit: 1
        )
        |> repo().one()

      # Fall back to default location if no "Pantry" location
      location_id =
        if location do
          location.id
        else
          default =
            from(l in "storage_locations",
              where: l.household_id == ^recipe.household_id and l.is_default == true,
              select: %{id: l.id},
              limit: 1
            )
            |> repo().one()

          default && default.id
        end

      if location_id do
        for ingredient <- ingredients do
          # Try to find existing pantry item by name (case-insensitive)
          pantry_item =
            from(p in "pantry_items",
              where:
                p.household_id == ^recipe.household_id and
                  fragment("LOWER(?)", p.name) == ^String.downcase(ingredient.name),
              select: %{id: p.id},
              limit: 1
            )
            |> repo().one()

          pantry_item_id =
            if pantry_item do
              pantry_item.id
            else
              # Create a new pantry item with quantity 0
              new_id = Ecto.UUID.dump!(Ecto.UUID.generate())
              now = DateTime.utc_now() |> DateTime.truncate(:second)

              repo().insert_all("pantry_items", [
                %{
                  id: new_id,
                  name: ingredient.name,
                  quantity: Decimal.new("0"),
                  unit: ingredient.unit,
                  household_id: recipe.household_id,
                  storage_location_id: location_id,
                  always_in_stock: false,
                  inserted_at: now,
                  updated_at: now
                }
              ])

              new_id
            end

          # Link the ingredient to the pantry item
          from(i in "recipe_ingredients", where: i.id == ^ingredient.id)
          |> repo().update_all(set: [pantry_item_id: pantry_item_id])
        end
      end
    end
  end

  def down do
    # No-op: we don't unlink ingredients on rollback
    :ok
  end
end
