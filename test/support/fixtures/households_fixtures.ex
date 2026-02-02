defmodule FeedMe.HouseholdsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FeedMe.Households` context.
  """

  alias FeedMe.AccountsFixtures

  def unique_household_name, do: "Household #{System.unique_integer()}"
  def unique_email, do: "user#{System.unique_integer()}@example.com"

  @doc """
  Generate a household with the given user as admin.
  """
  def household_fixture(attrs \\ %{}, user \\ nil) do
    user = user || AccountsFixtures.user_fixture()

    {:ok, household} =
      attrs
      |> Enum.into(%{name: unique_household_name()})
      |> FeedMe.Households.create_household(user)

    household
  end

  @doc """
  Generate an invitation.
  """
  def invitation_fixture(household, inviter, attrs \\ %{}) do
    {:ok, invitation} =
      attrs
      |> Enum.into(%{
        email: unique_email(),
        role: :member,
        household_id: household.id
      })
      |> FeedMe.Households.create_invitation(inviter)

    invitation
  end
end
