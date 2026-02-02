defmodule FeedMe.Households.Household do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "households" do
    field :name, :string
    field :selected_model, :string, default: "anthropic/claude-3.5-sonnet"

    has_many :memberships, FeedMe.Households.Membership
    has_many :users, through: [:memberships, :user]
    has_many :invitations, FeedMe.Households.Invitation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(household, attrs) do
    household
    |> cast(attrs, [:name, :selected_model])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end
end
