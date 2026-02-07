defmodule FeedMe.Pantry.StorageLocation do
  @moduledoc """
  Schema for storage locations within a household.

  Storage locations represent physical places where items are stored
  (e.g., Pantry, Garage, Pet Closet). Each household gets a default
  "On Hand" catch-all location and a "Pantry" location on creation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "storage_locations" do
    field :name, :string
    field :icon, :string
    field :sort_order, :integer, default: 0
    field :is_default, :boolean, default: false

    belongs_to :household, FeedMe.Households.Household
    has_many :categories, FeedMe.Pantry.Category
    has_many :items, FeedMe.Pantry.Item

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :icon, :sort_order, :is_default, :household_id])
    |> validate_required([:name, :household_id])
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:household_id)
    |> unique_constraint([:household_id, :name])
  end
end
