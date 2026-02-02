defmodule FeedMe.Suppliers.Supplier do
  @moduledoc """
  Schema for external grocery suppliers.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "suppliers" do
    field :name, :string
    field :code, :string
    field :api_base_url, :string
    field :logo_url, :string
    field :is_active, :boolean, default: true
    field :supports_aisle_sorting, :boolean, default: false
    field :supports_pricing, :boolean, default: false
    field :supports_delivery, :boolean, default: false
    field :config, :map, default: %{}

    has_many :household_suppliers, FeedMe.Suppliers.HouseholdSupplier

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(supplier, attrs) do
    supplier
    |> cast(attrs, [
      :name,
      :code,
      :api_base_url,
      :logo_url,
      :is_active,
      :supports_aisle_sorting,
      :supports_pricing,
      :supports_delivery,
      :config
    ])
    |> validate_required([:name, :code])
    |> unique_constraint(:code)
  end
end
