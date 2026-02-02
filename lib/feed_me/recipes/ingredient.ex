defmodule FeedMe.Recipes.Ingredient do
  @moduledoc """
  Schema for recipe ingredients.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recipe_ingredients" do
    field :name, :string
    field :quantity, :decimal
    field :unit, :string
    field :notes, :string
    field :optional, :boolean, default: false
    field :sort_order, :integer, default: 0

    belongs_to :recipe, FeedMe.Recipes.Recipe
    belongs_to :pantry_item, FeedMe.Pantry.Item

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:name, :quantity, :unit, :notes, :optional, :sort_order, :recipe_id, :pantry_item_id])
    |> validate_required([:name, :recipe_id])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:recipe_id)
    |> foreign_key_constraint(:pantry_item_id)
  end
end
