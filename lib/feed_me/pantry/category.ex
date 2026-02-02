defmodule FeedMe.Pantry.Category do
  @moduledoc """
  Schema for pantry categories.

  Categories help organize pantry items and can be sorted per household preference.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pantry_categories" do
    field :name, :string
    field :sort_order, :integer, default: 0
    field :icon, :string

    belongs_to :household, FeedMe.Households.Household
    has_many :items, FeedMe.Pantry.Item

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :sort_order, :icon, :household_id])
    |> validate_required([:name, :household_id])
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:household_id)
    |> unique_constraint([:household_id, :name])
  end
end
