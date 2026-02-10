defmodule FeedMe.Suppliers do
  @moduledoc """
  The Suppliers context manages external grocery supplier integrations.
  """

  import Ecto.Query, warn: false
  alias FeedMe.Repo
  alias FeedMe.Suppliers.{HouseholdSupplier, Supplier}

  # =============================================================================
  # Suppliers
  # =============================================================================

  @doc """
  Lists all active system (global) suppliers.
  """
  def list_suppliers do
    Supplier
    |> where([s], s.is_active == true and is_nil(s.household_id))
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists custom suppliers created by a household.
  """
  def list_custom_suppliers(household_id) do
    Supplier
    |> where([s], s.household_id == ^household_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Lists all suppliers available to a household (system + custom).
  """
  def list_available_suppliers(household_id) do
    Supplier
    |> where(
      [s],
      (s.is_active == true and is_nil(s.household_id)) or s.household_id == ^household_id
    )
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Gets a supplier by ID.
  """
  def get_supplier(id), do: Repo.get(Supplier, id)

  @doc """
  Gets a supplier by code.
  """
  def get_supplier_by_code(code) do
    Supplier
    |> where([s], s.code == ^code)
    |> Repo.one()
  end

  @doc """
  Creates a supplier.
  """
  def create_supplier(attrs) do
    %Supplier{}
    |> Supplier.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a supplier.
  """
  def update_supplier(%Supplier{} = supplier, attrs) do
    supplier
    |> Supplier.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a supplier (only custom/household-owned suppliers).
  """
  def delete_supplier(%Supplier{} = supplier) do
    Repo.delete(supplier)
  end

  @doc """
  Returns a changeset for a supplier.
  """
  def change_supplier(%Supplier{} = supplier, attrs \\ %{}) do
    Supplier.changeset(supplier, attrs)
  end

  @doc """
  Generates a deep link search URL for a supplier and product query.
  """
  def generate_deep_link(%Supplier{deep_link_search_template: nil}, _query), do: nil

  def generate_deep_link(%Supplier{deep_link_search_template: template}, query) do
    String.replace(template, "{query}", URI.encode_www_form(query))
  end

  @doc """
  Seeds default suppliers.
  """
  def seed_default_suppliers do
    suppliers = [
      %{
        name: "Instacart",
        code: "instacart",
        supports_aisle_sorting: true,
        supports_pricing: true,
        supports_delivery: true
      },
      %{
        name: "Amazon Fresh",
        code: "amazon_fresh",
        supports_aisle_sorting: false,
        supports_pricing: true,
        supports_delivery: true
      },
      %{
        name: "Walmart Grocery",
        code: "walmart",
        supports_aisle_sorting: true,
        supports_pricing: true,
        supports_delivery: true
      },
      %{
        name: "Kroger",
        code: "kroger",
        supports_aisle_sorting: true,
        supports_pricing: true,
        supports_delivery: true
      },
      %{
        name: "Target",
        code: "target",
        supports_aisle_sorting: false,
        supports_pricing: true,
        supports_delivery: true
      }
    ]

    Enum.each(suppliers, fn attrs ->
      case get_supplier_by_code(attrs.code) do
        nil -> create_supplier(attrs)
        _ -> :ok
      end
    end)
  end

  # =============================================================================
  # Household Suppliers
  # =============================================================================

  @doc """
  Lists suppliers enabled for a household.
  """
  def list_household_suppliers(household_id) do
    HouseholdSupplier
    |> where([hs], hs.household_id == ^household_id)
    |> preload(:supplier)
    |> Repo.all()
  end

  @doc """
  Gets the default supplier for a household.
  """
  def get_default_supplier(household_id) do
    HouseholdSupplier
    |> where([hs], hs.household_id == ^household_id and hs.is_default == true)
    |> preload(:supplier)
    |> Repo.one()
  end

  @doc """
  Gets a household supplier connection.
  """
  def get_household_supplier(household_id, supplier_id) do
    HouseholdSupplier
    |> where([hs], hs.household_id == ^household_id and hs.supplier_id == ^supplier_id)
    |> preload(:supplier)
    |> Repo.one()
  end

  @doc """
  Enables a supplier for a household.
  """
  def enable_supplier(household_id, supplier_id, user, opts \\ []) do
    attrs = %{
      household_id: household_id,
      supplier_id: supplier_id,
      configured_by_id: user.id,
      is_default: Keyword.get(opts, :is_default, false),
      api_credentials: Keyword.get(opts, :credentials)
    }

    %HouseholdSupplier{}
    |> HouseholdSupplier.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a household supplier connection.
  """
  def update_household_supplier(%HouseholdSupplier{} = hs, attrs) do
    hs
    |> HouseholdSupplier.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Disables a supplier for a household.
  """
  def disable_supplier(%HouseholdSupplier{} = hs) do
    Repo.delete(hs)
  end

  @doc """
  Sets a supplier as the default for a household.
  """
  def set_default_supplier(household_id, supplier_id) do
    Repo.transaction(fn ->
      # Clear existing default
      HouseholdSupplier
      |> where([hs], hs.household_id == ^household_id and hs.is_default == true)
      |> Repo.update_all(set: [is_default: false])

      # Set new default
      HouseholdSupplier
      |> where([hs], hs.household_id == ^household_id and hs.supplier_id == ^supplier_id)
      |> Repo.update_all(set: [is_default: true])
    end)
  end

  # =============================================================================
  # Supplier API (Placeholder for future implementation)
  # =============================================================================

  @doc """
  Searches for products from a supplier.
  This is a placeholder - actual implementation would call supplier APIs.
  """
  def search_products(_household_supplier, _query) do
    {:ok, []}
  end

  @doc """
  Gets product pricing from a supplier.
  This is a placeholder - actual implementation would call supplier APIs.
  """
  def get_product_price(_household_supplier, _product_id) do
    {:error, :not_implemented}
  end

  @doc """
  Adds items to supplier cart.
  This is a placeholder - actual implementation would call supplier APIs.
  """
  def add_to_cart(_household_supplier, _items) do
    {:error, :not_implemented}
  end

  @doc """
  Gets aisle information for a product.
  This is a placeholder - actual implementation would call supplier APIs.
  """
  def get_aisle_info(_household_supplier, _product_id) do
    {:error, :not_implemented}
  end
end
