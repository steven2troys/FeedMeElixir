defmodule FeedMe.Profiles do
  @moduledoc """
  The Profiles context manages taste profiles for users within households.
  """

  import Ecto.Query, warn: false
  alias FeedMe.Profiles.TasteProfile
  alias FeedMe.Repo

  @doc """
  Gets a taste profile for a user in a household.
  """
  def get_taste_profile(user_id, household_id) do
    TasteProfile
    |> where([t], t.user_id == ^user_id and t.household_id == ^household_id)
    |> Repo.one()
  end

  @doc """
  Gets or creates a taste profile for a user in a household.
  """
  def get_or_create_taste_profile(user_id, household_id) do
    case get_taste_profile(user_id, household_id) do
      nil ->
        {:ok, profile} = create_taste_profile(%{user_id: user_id, household_id: household_id})
        profile

      profile ->
        profile
    end
  end

  @doc """
  Lists all taste profiles for a household.
  """
  def list_taste_profiles_for_household(household_id) do
    TasteProfile
    |> where([t], t.household_id == ^household_id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Creates a taste profile.
  """
  def create_taste_profile(attrs) do
    %TasteProfile{}
    |> TasteProfile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a taste profile.
  """
  def update_taste_profile(%TasteProfile{} = taste_profile, attrs) do
    taste_profile
    |> TasteProfile.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a taste profile.
  """
  def delete_taste_profile(%TasteProfile{} = taste_profile) do
    Repo.delete(taste_profile)
  end

  @doc """
  Returns a changeset for tracking taste profile changes.
  """
  def change_taste_profile(%TasteProfile{} = taste_profile, attrs \\ %{}) do
    TasteProfile.changeset(taste_profile, attrs)
  end

  @doc """
  Gets a taste profile for a household (first one found, or creates one).
  Useful for AI context where we need any household profile.
  """
  def get_or_create_profile(household_id) do
    case list_taste_profiles_for_household(household_id) do
      [] ->
        {:error, :no_profiles}

      [profile | _] ->
        {:ok, profile}
    end
  end

  @doc """
  Returns a human-readable summary of a taste profile.
  """
  def dietary_summary(%TasteProfile{} = profile) do
    parts = []

    parts =
      if profile.dietary_restrictions != [] do
        parts ++ [Enum.join(profile.dietary_restrictions, ", ")]
      else
        parts
      end

    parts =
      if profile.allergies != [] do
        parts ++ ["allergic to " <> Enum.join(profile.allergies, ", ")]
      else
        parts
      end

    case parts do
      [] -> "No restrictions"
      parts -> Enum.join(parts, "; ")
    end
  end

  @doc """
  Gets combined restrictions/allergies for all household members.
  Useful for AI recommendations.
  """
  def get_household_dietary_summary(household_id) do
    profiles = list_taste_profiles_for_household(household_id)

    %{
      all_restrictions: profiles |> Enum.flat_map(& &1.dietary_restrictions) |> Enum.uniq(),
      all_allergies: profiles |> Enum.flat_map(& &1.allergies) |> Enum.uniq(),
      all_dislikes: profiles |> Enum.flat_map(& &1.dislikes) |> Enum.uniq(),
      common_favorites: find_common_items(profiles, :favorites)
    }
  end

  defp find_common_items(profiles, field) do
    case profiles do
      [] ->
        []

      profiles ->
        profiles
        |> Enum.map(&Map.get(&1, field, []))
        |> Enum.reduce(fn list, acc ->
          MapSet.intersection(MapSet.new(acc), MapSet.new(list)) |> MapSet.to_list()
        end)
    end
  end
end
