defmodule FeedMe.Procurement.ProcurementItem do
  @moduledoc """
  Schema for individual items in a procurement plan.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "procurement_items" do
    field :name, :string
    field :quantity, :decimal
    field :unit, :string
    field :estimated_price, :decimal
    field :actual_price, :decimal

    field :status, Ecto.Enum,
      values: [:needed, :in_cart, :purchased, :skipped],
      default: :needed

    field :notes, :string
    field :deep_link_url, :string
    field :category, :string

    belongs_to :procurement_plan, FeedMe.Procurement.ProcurementPlan
    belongs_to :pantry_item, FeedMe.Pantry.Item
    belongs_to :supplier, FeedMe.Suppliers.Supplier
    belongs_to :shopping_item, FeedMe.Shopping.Item

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name,
      :quantity,
      :unit,
      :estimated_price,
      :actual_price,
      :status,
      :notes,
      :deep_link_url,
      :category,
      :procurement_plan_id,
      :pantry_item_id,
      :supplier_id,
      :shopping_item_id
    ])
    |> validate_required([:name, :procurement_plan_id])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:estimated_price, greater_than_or_equal_to: 0)
    |> validate_number(:actual_price, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:procurement_plan_id)
    |> foreign_key_constraint(:pantry_item_id)
    |> foreign_key_constraint(:supplier_id)
    |> foreign_key_constraint(:shopping_item_id)
  end
end
