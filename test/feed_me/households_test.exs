defmodule FeedMe.HouseholdsTest do
  use FeedMe.DataCase

  alias FeedMe.Households
  alias FeedMe.Households.{Household, Membership, Invitation}
  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures

  describe "households" do
    test "list_households_for_user/1 returns households for the user" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      households = Households.list_households_for_user(user)
      assert length(households) == 1
      assert hd(households).household.id == household.id
      assert hd(households).role == :admin
    end

    test "get_household/1 returns the household" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      assert Households.get_household(household.id).id == household.id
    end

    test "get_household_for_user/2 returns the household with role" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      result = Households.get_household_for_user(household.id, user)
      assert result.household.id == household.id
      assert result.role == :admin
    end

    test "get_household_for_user/2 returns nil for non-member" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      assert Households.get_household_for_user(household.id, other_user) == nil
    end

    test "create_household/2 creates a household and makes user admin" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, %Household{} = household} =
               Households.create_household(%{name: "Test Household"}, user)

      assert household.name == "Test Household"
      assert Households.admin?(user, household.id)
    end

    test "create_household/2 with invalid data returns error changeset" do
      user = AccountsFixtures.user_fixture()

      assert {:error, %Ecto.Changeset{}} = Households.create_household(%{name: ""}, user)
    end

    test "update_household/2 updates the household" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      assert {:ok, %Household{} = updated} =
               Households.update_household(household, %{name: "Updated Name"})

      assert updated.name == "Updated Name"
    end

    test "delete_household/1 deletes the household" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      assert {:ok, %Household{}} = Households.delete_household(household)
      assert Households.get_household(household.id) == nil
    end
  end

  describe "memberships" do
    test "list_members/1 returns all members of a household" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      members = Households.list_members(household.id)
      assert length(members) == 1
      assert hd(members).user.id == user.id
      assert hd(members).role == :admin
    end

    test "get_membership/2 returns the membership" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      membership = Households.get_membership(user.id, household.id)
      assert membership.user_id == user.id
      assert membership.household_id == household.id
      assert membership.role == :admin
    end

    test "admin?/2 returns true for admins" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      assert Households.admin?(user, household.id)
    end

    test "admin?/2 returns false for non-admins" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      refute Households.admin?(other_user, household.id)
    end

    test "member?/2 returns true for members" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      assert Households.member?(user, household.id)
    end

    test "member?/2 returns false for non-members" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      refute Households.member?(other_user, household.id)
    end

    test "update_member_role/2 updates the member's role" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      membership = Households.get_membership(user.id, household.id)

      assert {:ok, %Membership{} = updated} =
               Households.update_member_role(membership.id, :member)

      assert updated.role == :member
    end

    test "remove_member/1 removes the member" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      membership = Households.get_membership(user.id, household.id)

      assert {:ok, %Membership{}} = Households.remove_member(membership.id)
      refute Households.member?(user, household.id)
    end
  end

  describe "invitations" do
    test "list_pending_invitations/1 returns pending invitations" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      invitation = HouseholdsFixtures.invitation_fixture(household, user)

      invitations = Households.list_pending_invitations(household.id)
      assert length(invitations) == 1
      assert hd(invitations).id == invitation.id
    end

    test "get_invitation_by_token/1 returns the invitation" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      invitation = HouseholdsFixtures.invitation_fixture(household, user)

      found = Households.get_invitation_by_token(invitation.token)
      assert found.id == invitation.id
    end

    test "create_invitation/2 creates a join_household invitation" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      assert {:ok, %Invitation{} = invitation} =
               Households.create_invitation(
                 %{email: "invited@example.com", type: :join_household, household_id: household.id},
                 user
               )

      assert invitation.email == "invited@example.com"
      assert invitation.type == :join_household
      assert invitation.role == :member
      assert invitation.token != nil
      assert invitation.expires_at != nil
    end

    test "create_invitation/2 creates a new_household invitation with admin role" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      assert {:ok, %Invitation{} = invitation} =
               Households.create_invitation(
                 %{email: "invited@example.com", type: :new_household, household_id: household.id},
                 user
               )

      assert invitation.email == "invited@example.com"
      assert invitation.type == :new_household
      assert invitation.role == :admin
    end

    test "accept_invitation/3 for join_household creates a membership" do
      admin = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, admin)
      new_user = AccountsFixtures.user_fixture()

      invitation =
        HouseholdsFixtures.invitation_fixture(household, admin, %{email: new_user.email})

      assert {:ok, %Membership{} = membership} =
               Households.accept_invitation(invitation, new_user)

      assert membership.user_id == new_user.id
      assert membership.household_id == household.id
      assert Households.member?(new_user, household.id)
    end

    test "accept_invitation/3 for new_household creates a new household" do
      admin = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, admin)
      new_user = AccountsFixtures.user_fixture()

      invitation =
        HouseholdsFixtures.invitation_fixture(household, admin, %{
          email: new_user.email,
          type: :new_household
        })

      assert {:ok, %Household{} = new_household} =
               Households.accept_invitation(invitation, new_user, household_name: "New Home")

      assert new_household.name == "New Home"
      assert Households.admin?(new_user, new_household.id)
      # The new user should NOT be a member of the original household
      refute Households.member?(new_user, household.id)
    end

    test "accept_invitation/3 returns error for expired invitation" do
      admin = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, admin)
      new_user = AccountsFixtures.user_fixture()

      invitation =
        HouseholdsFixtures.invitation_fixture(household, admin, %{email: new_user.email})

      # Manually expire the invitation
      expired_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
      Repo.update!(Ecto.Changeset.change(invitation, expires_at: expired_at))
      invitation = Repo.reload!(invitation)

      assert {:error, :expired} = Households.accept_invitation(invitation, new_user)
    end

    test "accept_invitation/3 returns error if already member for join_household" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      invitation = HouseholdsFixtures.invitation_fixture(household, user)

      assert {:error, :already_member} = Households.accept_invitation(invitation, user)
    end

    test "revoke_invitation/1 deletes the invitation" do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      invitation = HouseholdsFixtures.invitation_fixture(household, user)

      assert {:ok, %Invitation{}} = Households.revoke_invitation(invitation.id)
      assert Households.get_invitation_by_token(invitation.token) == nil
    end

    test "get_pending_invitations_for_email/1 returns invitations for email" do
      admin = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, admin)
      email = "test@example.com"
      invitation = HouseholdsFixtures.invitation_fixture(household, admin, %{email: email})

      invitations = Households.get_pending_invitations_for_email(email)
      assert length(invitations) == 1
      assert hd(invitations).id == invitation.id
    end
  end
end
