defmodule FeedMe.Repo.Migrations.AddNutritionData do
  use Ecto.Migration

  def change do
    alter table(:pantry_items) do
      add :nutrition, :map, default: nil
    end

    alter table(:recipe_ingredients) do
      add :nutrition, :map, default: nil
    end

    alter table(:taste_profiles) do
      add :nutrition_display, :string, default: "none", null: false
    end
  end
end
