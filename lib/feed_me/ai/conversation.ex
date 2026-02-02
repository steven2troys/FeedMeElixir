defmodule FeedMe.AI.Conversation do
  @moduledoc """
  Schema for AI chat conversations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ai_conversations" do
    field :title, :string
    field :model, :string
    field :status, Ecto.Enum, values: [:active, :archived], default: :active

    belongs_to :household, FeedMe.Households.Household
    belongs_to :started_by, FeedMe.Accounts.User
    has_many :messages, FeedMe.AI.Message, foreign_key: :conversation_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :model, :status, :household_id, :started_by_id])
    |> validate_required([:household_id])
    |> foreign_key_constraint(:household_id)
  end
end
