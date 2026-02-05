defmodule FeedMe.Repo.Migrations.CreateShoppingLists do
  use Ecto.Migration

  def change do
    # Shopping Lists
    create table(:shopping_lists, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :is_main, :boolean, default: false
      # active, completed, archived
      add :status, :string, default: "active"

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:shopping_lists, [:household_id])
    create index(:shopping_lists, [:household_id, :is_main])

    # Shopping List Items
    create table(:shopping_list_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :quantity, :decimal, default: 1
      add :unit, :string
      add :checked, :boolean, default: false
      add :checked_at, :utc_datetime
      add :aisle_location, :string
      add :notes, :string
      add :sort_order, :integer, default: 0

      add :shopping_list_id,
          references(:shopping_lists, type: :binary_id, on_delete: :delete_all), null: false

      add :pantry_item_id, references(:pantry_items, type: :binary_id, on_delete: :nilify_all)
      add :category_id, references(:pantry_categories, type: :binary_id, on_delete: :nilify_all)
      add :added_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :checked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:shopping_list_items, [:shopping_list_id])
    create index(:shopping_list_items, [:pantry_item_id])
    create index(:shopping_list_items, [:category_id])
    create index(:shopping_list_items, [:shopping_list_id, :checked])

    # Shopping Category Orders - per-household category sort order for shopping
    create table(:shopping_category_orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sort_order, :integer, default: 0

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :category_id, references(:pantry_categories, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:shopping_category_orders, [:household_id])
    create unique_index(:shopping_category_orders, [:household_id, :category_id])
  end
end
