defmodule FeedMe.Repo.Migrations.CreateMealPlanningTables do
  use Ecto.Migration

  def change do
    create table(:meal_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :start_date, :date, null: false
      add :end_date, :date, null: false
      add :status, :string, null: false, default: "draft"
      add :notes, :text
      add :ai_generated, :boolean, null: false, default: false

      add :household_id,
          references(:households, type: :binary_id, on_delete: :delete_all),
          null: false

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :approved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:meal_plans, [:household_id])
    create index(:meal_plans, [:status])
    create index(:meal_plans, [:start_date])

    create table(:meal_plan_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :date, :date, null: false
      add :meal_type, :string, null: false
      add :title, :string, null: false
      add :notes, :text
      add :servings, :integer
      add :sort_order, :integer, default: 0

      add :meal_plan_id,
          references(:meal_plans, type: :binary_id, on_delete: :delete_all),
          null: false

      add :recipe_id, references(:recipes, type: :binary_id, on_delete: :nilify_all)
      add :assigned_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:meal_plan_items, [:meal_plan_id])
    create index(:meal_plan_items, [:date])
    create index(:meal_plan_items, [:recipe_id])
  end
end
