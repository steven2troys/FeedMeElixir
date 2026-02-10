defmodule FeedMe.Repo.Migrations.CreateProcurementTables do
  use Ecto.Migration

  def change do
    create table(:procurement_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :status, :string, null: false, default: "suggested"
      add :estimated_total, :decimal
      add :actual_total, :decimal
      add :notes, :text
      add :ai_generated, :boolean, null: false, default: false
      add :source, :string, null: false, default: "manual"

      add :household_id,
          references(:households, type: :binary_id, on_delete: :delete_all),
          null: false

      add :meal_plan_id,
          references(:meal_plans, type: :binary_id, on_delete: :nilify_all)

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :approved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:procurement_plans, [:household_id])
    create index(:procurement_plans, [:status])
    create index(:procurement_plans, [:meal_plan_id])

    create table(:procurement_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :quantity, :decimal
      add :unit, :string
      add :estimated_price, :decimal
      add :actual_price, :decimal
      add :status, :string, null: false, default: "needed"
      add :notes, :text
      add :deep_link_url, :string
      add :category, :string

      add :procurement_plan_id,
          references(:procurement_plans, type: :binary_id, on_delete: :delete_all),
          null: false

      add :pantry_item_id,
          references(:pantry_items, type: :binary_id, on_delete: :nilify_all)

      add :supplier_id,
          references(:suppliers, type: :binary_id, on_delete: :nilify_all)

      add :shopping_item_id,
          references(:shopping_list_items, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:procurement_items, [:procurement_plan_id])
    create index(:procurement_items, [:supplier_id])
    create index(:procurement_items, [:status])
  end
end
