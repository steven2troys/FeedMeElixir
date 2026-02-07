defmodule FeedMe.Repo.Migrations.AddStorageLocations do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # 1. Create storage_locations table
    create table(:storage_locations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :icon, :string
      add :sort_order, :integer, default: 0
      add :is_default, :boolean, default: false, null: false

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:storage_locations, [:household_id, :name])
    create index(:storage_locations, [:household_id])

    # Flush DDL so the table exists for data inserts
    flush()

    # 2. For each existing household, insert "On Hand" and "Pantry" locations
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()

    household_ids =
      repo().all(
        from(h in "households",
          select: h.id
        )
      )

    # Build a map of household_id -> {on_hand_id, pantry_id}
    location_map =
      Enum.reduce(household_ids, %{}, fn household_id, acc ->
        on_hand_id = Ecto.UUID.generate()
        pantry_id = Ecto.UUID.generate()

        repo().insert_all("storage_locations", [
          %{
            id: Ecto.UUID.dump!(on_hand_id),
            name: "On Hand",
            icon: "hero-inbox-stack",
            sort_order: 0,
            is_default: true,
            household_id: household_id,
            inserted_at: now,
            updated_at: now
          },
          %{
            id: Ecto.UUID.dump!(pantry_id),
            name: "Pantry",
            icon: "hero-archive-box",
            sort_order: 1,
            is_default: false,
            household_id: household_id,
            inserted_at: now,
            updated_at: now
          }
        ])

        Map.put(acc, household_id, %{on_hand_id: on_hand_id, pantry_id: pantry_id})
      end)

    # 3. Add storage_location_id to pantry_categories (nullable first for backfill)
    alter table(:pantry_categories) do
      add :storage_location_id,
          references(:storage_locations, type: :binary_id, on_delete: :delete_all)
    end

    flush()

    # Backfill categories -> their household's "Pantry" location
    # Note: household_id is already raw binary from the query; pantry_id is a string UUID
    for {household_id, %{pantry_id: pantry_id}} <- location_map do
      repo().query!(
        "UPDATE pantry_categories SET storage_location_id = $1 WHERE household_id = $2",
        [Ecto.UUID.dump!(pantry_id), household_id]
      )
    end

    # 4. Add storage_location_id to pantry_items (nullable first for backfill)
    alter table(:pantry_items) do
      add :storage_location_id,
          references(:storage_locations, type: :binary_id, on_delete: :restrict)
    end

    flush()

    # Backfill items -> their household's "Pantry" location
    for {household_id, %{pantry_id: pantry_id}} <- location_map do
      repo().query!(
        "UPDATE pantry_items SET storage_location_id = $1 WHERE household_id = $2",
        [Ecto.UUID.dump!(pantry_id), household_id]
      )
    end

    # 5. Add auto_add_to_location_id to shopping_lists
    alter table(:shopping_lists) do
      add :auto_add_to_location_id,
          references(:storage_locations, type: :binary_id, on_delete: :nilify_all)
    end

    # Backfill: where add_to_pantry = true -> household's "Pantry" location
    flush()

    for {household_id, %{pantry_id: pantry_id}} <- location_map do
      repo().query!(
        "UPDATE shopping_lists SET auto_add_to_location_id = $1 WHERE household_id = $2 AND add_to_pantry = true",
        [Ecto.UUID.dump!(pantry_id), household_id]
      )
    end

    # 6. Drop old unique index on categories, add new one scoped to location
    drop_if_exists unique_index(:pantry_categories, [:household_id, :name])
    create unique_index(:pantry_categories, [:storage_location_id, :name])
    create index(:pantry_items, [:storage_location_id])

    # 7. Make storage_location_id NOT NULL after backfill
    alter table(:pantry_categories) do
      modify :storage_location_id, :binary_id, null: false
    end

    alter table(:pantry_items) do
      modify :storage_location_id, :binary_id, null: false
    end
  end

  def down do
    # Restore old unique constraint on categories
    drop_if_exists unique_index(:pantry_categories, [:storage_location_id, :name])
    drop_if_exists index(:pantry_items, [:storage_location_id])

    # Remove auto_add_to_location_id from shopping_lists
    alter table(:shopping_lists) do
      remove :auto_add_to_location_id
    end

    # Remove storage_location_id from pantry_items
    alter table(:pantry_items) do
      remove :storage_location_id
    end

    # Remove storage_location_id from pantry_categories
    alter table(:pantry_categories) do
      remove :storage_location_id
    end

    create unique_index(:pantry_categories, [:household_id, :name])

    # Drop storage_locations table
    drop table(:storage_locations)
  end
end
