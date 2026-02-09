defmodule FeedMe.Pantry.Item do
  @moduledoc """
  Schema for pantry items.

  Items track inventory with optional auto-restock settings.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pantry_items" do
    field :name, :string
    field :quantity, :decimal, default: Decimal.new(0)
    field :unit, :string
    field :expiration_date, :date
    field :always_in_stock, :boolean, default: false
    field :restock_threshold, :decimal
    field :is_standard, :boolean, default: false
    field :notes, :string
    field :barcode, :string

    belongs_to :household, FeedMe.Households.Household
    belongs_to :storage_location, FeedMe.Pantry.StorageLocation
    belongs_to :category, FeedMe.Pantry.Category
    has_many :transactions, FeedMe.Pantry.Transaction, foreign_key: :pantry_item_id

    embeds_one :nutrition, FeedMe.Nutrition.Info, on_replace: :update

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name,
      :quantity,
      :unit,
      :expiration_date,
      :always_in_stock,
      :restock_threshold,
      :is_standard,
      :notes,
      :barcode,
      :household_id,
      :storage_location_id,
      :category_id
    ])
    |> validate_required([:name, :household_id, :storage_location_id])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_number(:restock_threshold, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:household_id)
    |> foreign_key_constraint(:storage_location_id)
    |> foreign_key_constraint(:category_id)
    |> cast_embed(:nutrition)
  end

  @doc """
  Changeset for updating just the nutrition data.
  """
  def nutrition_changeset(item, attrs) do
    item
    |> cast(attrs, [])
    |> cast_embed(:nutrition)
  end

  @doc """
  Returns true if the item needs restocking.

  An item needs restocking when:
  - It has always_in_stock set to true, AND
  - Its quantity is at or below the restock_threshold (or 0 if no threshold)
  """
  def needs_restock?(%__MODULE__{always_in_stock: false}), do: false

  def needs_restock?(%__MODULE__{
        always_in_stock: true,
        quantity: qty,
        restock_threshold: threshold
      }) do
    threshold = threshold || Decimal.new(0)
    Decimal.compare(qty, threshold) != :gt
  end

  @doc """
  Returns true if the item is expired.
  """
  def expired?(%__MODULE__{expiration_date: nil}), do: false

  def expired?(%__MODULE__{expiration_date: date}) do
    Date.compare(date, Date.utc_today()) == :lt
  end

  @doc """
  Returns true if the item expires within the given days.
  """
  def expiring_soon?(%__MODULE__{expiration_date: nil}, _days), do: false

  def expiring_soon?(%__MODULE__{expiration_date: date}, days) do
    days_until = Date.diff(date, Date.utc_today())
    days_until >= 0 and days_until <= days
  end
end
