defmodule FeedMe.Profiles.TasteProfile do
  @moduledoc """
  Schema for user taste profiles within a household.

  Each user can have different taste preferences per household they belong to.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "taste_profiles" do
    field :dietary_restrictions, {:array, :string}, default: []
    field :allergies, {:array, :string}, default: []
    field :dislikes, {:array, :string}, default: []
    field :favorites, {:array, :string}, default: []
    field :notes, :string

    belongs_to :user, FeedMe.Accounts.User
    belongs_to :household, FeedMe.Households.Household

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(taste_profile, attrs) do
    taste_profile
    |> cast(attrs, [
      :dietary_restrictions,
      :allergies,
      :dislikes,
      :favorites,
      :notes,
      :user_id,
      :household_id
    ])
    |> validate_required([:user_id, :household_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:household_id)
    |> unique_constraint([:user_id, :household_id])
    |> normalize_arrays()
  end

  defp normalize_arrays(changeset) do
    # Remove empty strings and duplicates from arrays
    Enum.reduce([:dietary_restrictions, :allergies, :dislikes, :favorites], changeset, fn field,
                                                                                          cs ->
      case get_change(cs, field) do
        nil ->
          cs

        values when is_list(values) ->
          normalized =
            values
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))
            |> Enum.uniq()

          put_change(cs, field, normalized)

        _ ->
          cs
      end
    end)
  end
end
