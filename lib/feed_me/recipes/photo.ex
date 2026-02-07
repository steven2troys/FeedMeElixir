defmodule FeedMe.Recipes.Photo do
  @moduledoc """
  Schema for recipe photos.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recipe_photos" do
    field :url, :string
    field :caption, :string
    field :sort_order, :integer, default: 0
    field :is_primary, :boolean, default: false

    belongs_to :recipe, FeedMe.Recipes.Recipe

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:url, :caption, :sort_order, :is_primary, :recipe_id])
    |> validate_required([:url, :recipe_id])
    |> validate_format(:url, ~r/^(https?:\/\/|\/uploads\/)/, message: "must be a valid URL")
    |> foreign_key_constraint(:recipe_id)
  end
end
