defmodule FeedMe.Recipes.CookingLog do
  @moduledoc """
  Schema for cooking logs - history of cooked meals.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "cooking_logs" do
    field :servings_made, :integer
    field :notes, :string
    field :rating, :integer

    belongs_to :recipe, FeedMe.Recipes.Recipe
    belongs_to :cooked_by, FeedMe.Accounts.User
    belongs_to :household, FeedMe.Households.Household

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(cooking_log, attrs) do
    cooking_log
    |> cast(attrs, [:servings_made, :notes, :rating, :recipe_id, :cooked_by_id, :household_id])
    |> validate_required([:recipe_id, :household_id])
    |> validate_number(:servings_made, greater_than: 0)
    |> validate_inclusion(:rating, 1..5)
    |> foreign_key_constraint(:recipe_id)
    |> foreign_key_constraint(:cooked_by_id)
    |> foreign_key_constraint(:household_id)
  end
end
