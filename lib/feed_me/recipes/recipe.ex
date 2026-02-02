defmodule FeedMe.Recipes.Recipe do
  @moduledoc """
  Schema for recipes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recipes" do
    field :title, :string
    field :description, :string
    field :instructions, :string
    field :prep_time_minutes, :integer
    field :cook_time_minutes, :integer
    field :servings, :integer
    field :source_url, :string
    field :source_name, :string
    field :is_favorite, :boolean, default: false
    field :tags, {:array, :string}, default: []

    belongs_to :household, FeedMe.Households.Household
    belongs_to :created_by, FeedMe.Accounts.User

    has_many :ingredients, FeedMe.Recipes.Ingredient
    has_many :photos, FeedMe.Recipes.Photo
    has_many :cooking_logs, FeedMe.Recipes.CookingLog

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [
      :title,
      :description,
      :instructions,
      :prep_time_minutes,
      :cook_time_minutes,
      :servings,
      :source_url,
      :source_name,
      :is_favorite,
      :tags,
      :household_id,
      :created_by_id
    ])
    |> validate_required([:title, :household_id])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_number(:prep_time_minutes, greater_than_or_equal_to: 0)
    |> validate_number(:cook_time_minutes, greater_than_or_equal_to: 0)
    |> validate_number(:servings, greater_than: 0)
    |> foreign_key_constraint(:household_id)
    |> foreign_key_constraint(:created_by_id)
    |> normalize_tags()
  end

  defp normalize_tags(changeset) do
    case get_change(changeset, :tags) do
      nil ->
        changeset

      tags when is_list(tags) ->
        normalized =
          tags
          |> Enum.map(&String.trim/1)
          |> Enum.map(&String.downcase/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        put_change(changeset, :tags, normalized)

      _ ->
        changeset
    end
  end

  @doc """
  Returns the total time for a recipe.
  """
  def total_time(%__MODULE__{prep_time_minutes: prep, cook_time_minutes: cook}) do
    (prep || 0) + (cook || 0)
  end
end
