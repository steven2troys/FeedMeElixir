defmodule FeedMe.Repo.Migrations.CreateProfilesAndPantry do
  use Ecto.Migration

  def change do
    # Taste Profiles - one per user per household
    create table(:taste_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :dietary_restrictions, {:array, :string}, default: []
      add :allergies, {:array, :string}, default: []
      add :dislikes, {:array, :string}, default: []
      add :favorites, {:array, :string}, default: []
      add :notes, :text

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:taste_profiles, [:user_id])
    create index(:taste_profiles, [:household_id])
    create unique_index(:taste_profiles, [:user_id, :household_id])

    # Pantry Categories - sortable categories per household
    create table(:pantry_categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :sort_order, :integer, default: 0
      add :icon, :string

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:pantry_categories, [:household_id])
    create unique_index(:pantry_categories, [:household_id, :name])

    # Pantry Items - inventory items
    create table(:pantry_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :quantity, :decimal, default: 0
      add :unit, :string
      add :expiration_date, :date
      add :always_in_stock, :boolean, default: false
      add :restock_threshold, :decimal
      add :is_standard, :boolean, default: false
      add :notes, :text
      add :barcode, :string

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :category_id, references(:pantry_categories, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:pantry_items, [:household_id])
    create index(:pantry_items, [:category_id])
    create index(:pantry_items, [:household_id, :name])
    create index(:pantry_items, [:barcode])

    # Pantry Transactions - audit trail for changes
    create table(:pantry_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # add, remove, adjust, use
      add :action, :string, null: false
      add :quantity_change, :decimal, null: false
      add :quantity_before, :decimal
      add :quantity_after, :decimal
      add :reason, :string
      add :notes, :text

      add :pantry_item_id, references(:pantry_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:pantry_transactions, [:pantry_item_id])
    create index(:pantry_transactions, [:user_id])
    create index(:pantry_transactions, [:inserted_at])
  end
end
