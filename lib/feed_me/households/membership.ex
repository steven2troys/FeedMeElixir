defmodule FeedMe.Households.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "memberships" do
    field :role, Ecto.Enum, values: [:admin, :member], default: :member

    belongs_to :user, FeedMe.Accounts.User
    belongs_to :household, FeedMe.Households.Household

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :user_id, :household_id])
    |> validate_required([:role, :user_id, :household_id])
    |> validate_inclusion(:role, [:admin, :member])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:household_id)
    |> unique_constraint([:user_id, :household_id])
  end
end
