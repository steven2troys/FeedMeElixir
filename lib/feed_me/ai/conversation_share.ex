defmodule FeedMe.AI.ConversationShare do
  @moduledoc """
  Schema for sharing AI conversations with household members.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversation_shares" do
    belongs_to :conversation, FeedMe.AI.Conversation
    belongs_to :user, FeedMe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(share, attrs) do
    share
    |> cast(attrs, [:conversation_id, :user_id])
    |> validate_required([:conversation_id, :user_id])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:conversation_id, :user_id])
  end
end
