defmodule FeedMe.Households.Household do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "households" do
    field :name, :string
    field :selected_model, :string, default: "anthropic/claude-3.5-sonnet"
    field :timezone, :string, default: "America/Los_Angeles"

    field :automation_tier, Ecto.Enum,
      values: [:off, :recommend, :cart_fill, :auto_purchase],
      default: :off

    field :weekly_suggestion_enabled, :boolean, default: false
    field :weekly_suggestion_day, :integer, default: 7
    field :daily_pantry_check_enabled, :boolean, default: false

    has_many :memberships, FeedMe.Households.Membership
    has_many :users, through: [:memberships, :user]
    has_many :invitations, FeedMe.Households.Invitation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(household, attrs) do
    household
    |> cast(attrs, [
      :name,
      :selected_model,
      :timezone,
      :automation_tier,
      :weekly_suggestion_enabled,
      :weekly_suggestion_day,
      :daily_pantry_check_enabled
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end
end
