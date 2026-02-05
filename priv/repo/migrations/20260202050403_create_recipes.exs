defmodule FeedMe.Repo.Migrations.CreateRecipes do
  use Ecto.Migration

  def change do
    # Recipes
    create table(:recipes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :instructions, :text
      add :prep_time_minutes, :integer
      add :cook_time_minutes, :integer
      add :servings, :integer
      add :source_url, :string
      add :source_name, :string
      add :is_favorite, :boolean, default: false
      add :tags, {:array, :string}, default: []

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:recipes, [:household_id])
    create index(:recipes, [:household_id, :is_favorite])
    create index(:recipes, [:household_id, :title])

    # Recipe Ingredients
    create table(:recipe_ingredients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :quantity, :decimal
      add :unit, :string
      add :notes, :string
      add :optional, :boolean, default: false
      add :sort_order, :integer, default: 0

      add :recipe_id, references(:recipes, type: :binary_id, on_delete: :delete_all), null: false
      add :pantry_item_id, references(:pantry_items, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:recipe_ingredients, [:recipe_id])
    create index(:recipe_ingredients, [:pantry_item_id])

    # Recipe Photos
    create table(:recipe_photos, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url, :string, null: false
      add :caption, :string
      add :sort_order, :integer, default: 0
      add :is_primary, :boolean, default: false

      add :recipe_id, references(:recipes, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:recipe_photos, [:recipe_id])

    # Cooking Logs - history of cooked meals
    create table(:cooking_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :servings_made, :integer
      add :notes, :text
      # 1-5 stars
      add :rating, :integer

      add :recipe_id, references(:recipes, type: :binary_id, on_delete: :delete_all), null: false
      add :cooked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:cooking_logs, [:recipe_id])
    create index(:cooking_logs, [:household_id])
    create index(:cooking_logs, [:cooked_by_id])
    create index(:cooking_logs, [:inserted_at])
  end
end
