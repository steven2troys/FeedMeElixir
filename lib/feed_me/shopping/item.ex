defmodule FeedMe.Shopping.Item do
  @moduledoc """
  Schema for shopping list items.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "shopping_list_items" do
    field :name, :string
    field :quantity, :decimal, default: Decimal.new(1)
    field :unit, :string
    field :checked, :boolean, default: false
    field :checked_at, :utc_datetime
    field :aisle_location, :string
    field :notes, :string
    field :sort_order, :integer, default: 0

    belongs_to :shopping_list, FeedMe.Shopping.List
    belongs_to :pantry_item, FeedMe.Pantry.Item
    belongs_to :category, FeedMe.Pantry.Category
    belongs_to :added_by, FeedMe.Accounts.User
    belongs_to :checked_by, FeedMe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name,
      :quantity,
      :unit,
      :checked,
      :checked_at,
      :aisle_location,
      :notes,
      :sort_order,
      :shopping_list_id,
      :pantry_item_id,
      :category_id,
      :added_by_id,
      :checked_by_id
    ])
    |> validate_required([:name, :shopping_list_id])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:shopping_list_id)
    |> foreign_key_constraint(:pantry_item_id)
    |> foreign_key_constraint(:category_id)
  end

  @doc """
  Changeset for toggling the checked status.
  """
  def toggle_checked_changeset(item, user_id) do
    now = if item.checked, do: nil, else: DateTime.utc_now(:second)
    checked_by = if item.checked, do: nil, else: user_id

    item
    |> change(%{
      checked: not item.checked,
      checked_at: now,
      checked_by_id: checked_by
    })
  end
end
