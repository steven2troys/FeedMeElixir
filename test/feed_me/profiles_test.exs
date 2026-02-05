defmodule FeedMe.ProfilesTest do
  use FeedMe.DataCase

  alias FeedMe.Profiles
  alias FeedMe.Profiles.TasteProfile
  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures

  describe "taste_profiles" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "get_taste_profile/2 returns nil when no profile exists", %{
      user: user,
      household: household
    } do
      assert Profiles.get_taste_profile(user.id, household.id) == nil
    end

    test "create_taste_profile/1 creates a profile", %{user: user, household: household} do
      attrs = %{
        user_id: user.id,
        household_id: household.id,
        dietary_restrictions: ["vegetarian"],
        allergies: ["peanuts"]
      }

      assert {:ok, %TasteProfile{} = profile} = Profiles.create_taste_profile(attrs)
      assert profile.dietary_restrictions == ["vegetarian"]
      assert profile.allergies == ["peanuts"]
    end

    test "get_or_create_taste_profile/2 creates when none exists", %{
      user: user,
      household: household
    } do
      profile = Profiles.get_or_create_taste_profile(user.id, household.id)
      assert profile.user_id == user.id
      assert profile.household_id == household.id
    end

    test "get_or_create_taste_profile/2 returns existing profile", %{
      user: user,
      household: household
    } do
      {:ok, original} =
        Profiles.create_taste_profile(%{
          user_id: user.id,
          household_id: household.id,
          allergies: ["gluten"]
        })

      fetched = Profiles.get_or_create_taste_profile(user.id, household.id)
      assert fetched.id == original.id
      assert fetched.allergies == ["gluten"]
    end

    test "update_taste_profile/2 updates a profile", %{user: user, household: household} do
      profile = Profiles.get_or_create_taste_profile(user.id, household.id)

      {:ok, updated} =
        Profiles.update_taste_profile(profile, %{
          dietary_restrictions: ["vegan"],
          favorites: ["pizza", "tacos"]
        })

      assert updated.dietary_restrictions == ["vegan"]
      assert updated.favorites == ["pizza", "tacos"]
    end

    test "list_taste_profiles_for_household/1 returns all profiles", %{household: household} do
      user1 = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()

      # Add users to household
      FeedMe.Households.accept_invitation(
        FeedMe.HouseholdsFixtures.invitation_fixture(
          household,
          household |> FeedMe.Repo.preload(:users) |> then(& &1.users) |> hd(),
          %{email: user1.email}
        ),
        user1
      )

      FeedMe.Households.accept_invitation(
        FeedMe.HouseholdsFixtures.invitation_fixture(
          household,
          household |> FeedMe.Repo.preload(:users) |> then(& &1.users) |> hd(),
          %{email: user2.email}
        ),
        user2
      )

      Profiles.get_or_create_taste_profile(user1.id, household.id)
      Profiles.get_or_create_taste_profile(user2.id, household.id)

      profiles = Profiles.list_taste_profiles_for_household(household.id)
      assert length(profiles) == 2
    end

    test "changeset normalizes arrays", %{user: user, household: household} do
      {:ok, profile} =
        Profiles.create_taste_profile(%{
          user_id: user.id,
          household_id: household.id,
          allergies: ["peanuts", "  ", "peanuts", " dairy "]
        })

      # Should remove empty strings, trim, and dedupe
      assert profile.allergies == ["peanuts", "dairy"]
    end

    test "get_household_dietary_summary/1 aggregates all profiles", %{household: household} do
      user1 = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()

      # Add users and create profiles
      FeedMe.Households.accept_invitation(
        FeedMe.HouseholdsFixtures.invitation_fixture(
          household,
          household |> FeedMe.Repo.preload(:users) |> then(& &1.users) |> hd(),
          %{email: user1.email}
        ),
        user1
      )

      FeedMe.Households.accept_invitation(
        FeedMe.HouseholdsFixtures.invitation_fixture(
          household,
          household |> FeedMe.Repo.preload(:users) |> then(& &1.users) |> hd(),
          %{email: user2.email}
        ),
        user2
      )

      Profiles.create_taste_profile(%{
        user_id: user1.id,
        household_id: household.id,
        allergies: ["peanuts"],
        favorites: ["pizza", "tacos"]
      })

      Profiles.create_taste_profile(%{
        user_id: user2.id,
        household_id: household.id,
        allergies: ["dairy"],
        favorites: ["pizza", "sushi"]
      })

      summary = Profiles.get_household_dietary_summary(household.id)

      assert "peanuts" in summary.all_allergies
      assert "dairy" in summary.all_allergies
      # Only "pizza" is shared between both users
      assert summary.common_favorites == ["pizza"]
    end
  end
end
