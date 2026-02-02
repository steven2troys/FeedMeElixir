defmodule FeedMe.Pantry.Transaction do
  @moduledoc """
  Schema for pantry transactions.

  Transactions provide an audit trail for all inventory changes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pantry_transactions" do
    field :action, Ecto.Enum, values: [:add, :remove, :adjust, :use]
    field :quantity_change, :decimal
    field :quantity_before, :decimal
    field :quantity_after, :decimal
    field :reason, :string
    field :notes, :string

    belongs_to :pantry_item, FeedMe.Pantry.Item
    belongs_to :user, FeedMe.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :action,
      :quantity_change,
      :quantity_before,
      :quantity_after,
      :reason,
      :notes,
      :pantry_item_id,
      :user_id
    ])
    |> validate_required([:action, :quantity_change, :pantry_item_id])
    |> foreign_key_constraint(:pantry_item_id)
    |> foreign_key_constraint(:user_id)
  end
end
