defmodule FeedMe.Shopping.CategoryOrder do
  @moduledoc """
  Schema for shopping category sort orders per household.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "shopping_category_orders" do
    field :sort_order, :integer, default: 0

    belongs_to :household, FeedMe.Households.Household
    belongs_to :category, FeedMe.Pantry.Category

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category_order, attrs) do
    category_order
    |> cast(attrs, [:sort_order, :household_id, :category_id])
    |> validate_required([:household_id, :category_id])
    |> foreign_key_constraint(:household_id)
    |> foreign_key_constraint(:category_id)
    |> unique_constraint([:household_id, :category_id])
  end
end
