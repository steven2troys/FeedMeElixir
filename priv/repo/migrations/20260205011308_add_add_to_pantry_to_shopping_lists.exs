defmodule FeedMe.Repo.Migrations.AddAddToPantryToShoppingLists do
  use Ecto.Migration

  def change do
    alter table(:shopping_lists) do
      add :add_to_pantry, :boolean, default: false, null: false
    end

    # Backfill: main lists always have add_to_pantry enabled
    execute "UPDATE shopping_lists SET add_to_pantry = true WHERE is_main = true",
            "UPDATE shopping_lists SET add_to_pantry = false WHERE is_main = true"
  end
end
