defmodule FeedMe.AI.Message do
  @moduledoc """
  Schema for AI chat messages.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ai_messages" do
    field :role, Ecto.Enum, values: [:user, :assistant, :system, :tool]
    field :content, :string
    field :tool_calls, :map
    field :tool_call_id, :string
    field :metadata, :map

    belongs_to :conversation, FeedMe.AI.Conversation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :tool_calls, :tool_call_id, :metadata, :conversation_id])
    |> validate_required([:role, :conversation_id])
    |> foreign_key_constraint(:conversation_id)
  end
end
