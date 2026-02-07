defmodule FeedMe.Households do
  @moduledoc """
  The Households context manages households, memberships, and invitations.
  """

  import Ecto.Query, warn: false
  alias FeedMe.Repo
  alias FeedMe.Households.{Household, Membership, Invitation}
  alias FeedMe.Accounts.User

  # =============================================================================
  # Households
  # =============================================================================

  @doc """
  Returns the list of households for a user.
  """
  def list_households_for_user(%User{id: user_id}) do
    Membership
    |> where([m], m.user_id == ^user_id)
    |> join(:inner, [m], h in Household, on: m.household_id == h.id)
    |> select([m, h], %{household: h, role: m.role})
    |> Repo.all()
  end

  @doc """
  Returns the single household if the user belongs to exactly one, nil otherwise.
  Uses limit(2) for efficiency — avoids counting all memberships.
  """
  def get_single_household_for_user(%User{id: user_id}) do
    results =
      Membership
      |> where([m], m.user_id == ^user_id)
      |> join(:inner, [m], h in Household, on: m.household_id == h.id)
      |> select([m, h], h)
      |> limit(2)
      |> Repo.all()

    case results do
      [single] -> single
      _ -> nil
    end
  end

  @doc """
  Returns the number of households for a user.
  """
  def count_households_for_user(%User{id: user_id}) do
    Membership
    |> where([m], m.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets a single household.
  """
  def get_household(id) do
    Repo.get(Household, id)
  end

  @doc """
  Gets a household if the user is a member.
  """
  def get_household_for_user(household_id, %User{id: user_id}) do
    Membership
    |> where([m], m.user_id == ^user_id and m.household_id == ^household_id)
    |> join(:inner, [m], h in Household, on: m.household_id == h.id)
    |> select([m, h], %{household: h, role: m.role})
    |> Repo.one()
  end

  @doc """
  Creates a household and adds the creator as an admin.
  """
  def create_household(attrs, %User{id: user_id}) do
    Repo.transaction(fn ->
      with {:ok, household} <- %Household{} |> Household.changeset(attrs) |> Repo.insert(),
           {:ok, _membership} <-
             %Membership{}
             |> Membership.changeset(%{
               user_id: user_id,
               household_id: household.id,
               role: :admin
             })
             |> Repo.insert() do
        FeedMe.Pantry.create_default_locations(household.id)
        household
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates a household.
  """
  def update_household(%Household{} = household, attrs) do
    household
    |> Household.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a household.
  """
  def delete_household(%Household{} = household) do
    Repo.delete(household)
  end

  # =============================================================================
  # Memberships
  # =============================================================================

  @doc """
  Returns the list of members for a household.
  """
  def list_members(household_id) do
    Membership
    |> where([m], m.household_id == ^household_id)
    |> join(:inner, [m], u in User, on: m.user_id == u.id)
    |> select([m, u], %{user: u, role: m.role, membership_id: m.id})
    |> Repo.all()
  end

  @doc """
  Gets the membership for a user in a household.
  """
  def get_membership(user_id, household_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.household_id == ^household_id)
    |> Repo.one()
  end

  @doc """
  Checks if a user is an admin of a household.
  """
  def admin?(%User{id: user_id}, household_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.household_id == ^household_id and m.role == :admin)
    |> Repo.exists?()
  end

  @doc """
  Checks if a user is a member (any role) of a household.
  """
  def member?(%User{id: user_id}, household_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.household_id == ^household_id)
    |> Repo.exists?()
  end

  @doc """
  Updates a member's role.
  """
  def update_member_role(membership_id, role) do
    Membership
    |> Repo.get!(membership_id)
    |> Membership.changeset(%{role: role})
    |> Repo.update()
  end

  @doc """
  Removes a member from a household.
  """
  def remove_member(membership_id) do
    Membership
    |> Repo.get!(membership_id)
    |> Repo.delete()
  end

  # =============================================================================
  # Invitations
  # =============================================================================

  @doc """
  Returns the list of pending invitations for a household.
  """
  def list_pending_invitations(household_id) do
    now = DateTime.utc_now()

    Invitation
    |> where([i], i.household_id == ^household_id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^now)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets an invitation by token.
  """
  def get_invitation_by_token(token) do
    Invitation
    |> where([i], i.token == ^token)
    |> preload(:household)
    |> Repo.one()
  end

  @doc """
  Creates an invitation.
  """
  def create_invitation(attrs, %User{} = inviter) do
    %Invitation{}
    |> Invitation.changeset(Map.put(attrs, :invited_by_id, inviter.id))
    |> Repo.insert()
  end

  @doc """
  Accepts an invitation and creates a membership.
  """
  def accept_invitation(%Invitation{} = invitation, %User{} = user) do
    cond do
      Invitation.expired?(invitation) ->
        {:error, :expired}

      Invitation.accepted?(invitation) ->
        {:error, :already_accepted}

      member?(user, invitation.household_id) ->
        {:error, :already_member}

      true ->
        Repo.transaction(fn ->
          with {:ok, _invitation} <-
                 invitation |> Invitation.accept_changeset() |> Repo.update(),
               {:ok, membership} <-
                 %Membership{}
                 |> Membership.changeset(%{
                   user_id: user.id,
                   household_id: invitation.household_id,
                   role: invitation.role
                 })
                 |> Repo.insert() do
            membership
          else
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
    end
  end

  @doc """
  Revokes an invitation.
  """
  def revoke_invitation(invitation_id) do
    Invitation
    |> Repo.get!(invitation_id)
    |> Repo.delete()
  end

  @doc """
  Gets pending invitations for an email address.
  """
  def get_pending_invitations_for_email(email) do
    now = DateTime.utc_now()

    Invitation
    |> where([i], i.email == ^email)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^now)
    |> preload(:household)
    |> Repo.all()
  end
end
