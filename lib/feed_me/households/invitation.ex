defmodule FeedMe.Households.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invitations" do
    field :email, :string
    field :token, :string
    field :role, Ecto.Enum, values: [:admin, :member], default: :member
    field :type, Ecto.Enum, values: [:join_household, :new_household], default: :join_household
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :household, FeedMe.Households.Household
    belongs_to :invited_by, FeedMe.Accounts.User, foreign_key: :invited_by_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new invitation.
  """
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :type, :household_id, :invited_by_id])
    |> validate_required([:email, :type, :household_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> set_role_from_type()
    |> foreign_key_constraint(:household_id)
    |> foreign_key_constraint(:invited_by_id)
    |> generate_token()
    |> set_expiration()
  end

  defp set_role_from_type(changeset) do
    case get_field(changeset, :type) do
      :new_household -> put_change(changeset, :role, :admin)
      _ -> put_change(changeset, :role, :member)
    end
  end

  defp generate_token(changeset) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    put_change(changeset, :token, token)
  end

  defp set_expiration(changeset) do
    # Invitations expire in 7 days
    expires_at = DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second)
    put_change(changeset, :expires_at, expires_at)
  end

  @doc """
  Marks the invitation as accepted.
  """
  def accept_changeset(invitation) do
    change(invitation, accepted_at: DateTime.utc_now(:second))
  end

  @doc """
  Returns true if the invitation has expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Returns true if the invitation has been accepted.
  """
  def accepted?(%__MODULE__{accepted_at: accepted_at}) do
    accepted_at != nil
  end
end
