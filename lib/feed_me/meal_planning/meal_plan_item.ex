defmodule FeedMe.MealPlanning.MealPlanItem do
  @moduledoc """
  Schema for individual meals within a meal plan.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meal_plan_items" do
    field :date, :date
    field :meal_type, Ecto.Enum, values: [:breakfast, :lunch, :dinner, :snack]
    field :title, :string
    field :notes, :string
    field :servings, :integer
    field :sort_order, :integer, default: 0

    belongs_to :meal_plan, FeedMe.MealPlanning.MealPlan
    belongs_to :recipe, FeedMe.Recipes.Recipe
    belongs_to :assigned_by, FeedMe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :date,
      :meal_type,
      :title,
      :notes,
      :servings,
      :sort_order,
      :meal_plan_id,
      :recipe_id,
      :assigned_by_id
    ])
    |> validate_required([:date, :meal_type, :title, :meal_plan_id])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_number(:servings, greater_than: 0)
    |> foreign_key_constraint(:meal_plan_id)
    |> foreign_key_constraint(:recipe_id)
    |> foreign_key_constraint(:assigned_by_id)
  end
end
