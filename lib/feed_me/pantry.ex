defmodule FeedMe.Pantry do
  @moduledoc """
  The Pantry context manages inventory, categories, storage locations, and transactions.
  """

  import Ecto.Query, warn: false
  alias FeedMe.Pantry.{Category, Item, StorageLocation, Transaction}
  alias FeedMe.Repo

  @pubsub FeedMe.PubSub

  # =============================================================================
  # Category Templates
  # =============================================================================

  @category_templates %{
    pantry: [
      %{name: "Produce", icon: "hero-leaf", sort_order: 0},
      %{name: "Dairy", icon: "hero-beaker", sort_order: 1},
      %{name: "Meat & Seafood", icon: "hero-fire", sort_order: 2},
      %{name: "Pantry Staples", icon: "hero-archive-box", sort_order: 3},
      %{name: "Frozen", icon: "hero-cube", sort_order: 4},
      %{name: "Beverages", icon: "hero-beaker", sort_order: 5},
      %{name: "Snacks", icon: "hero-cake", sort_order: 6},
      %{name: "Condiments", icon: "hero-adjustments-horizontal", sort_order: 7}
    ],
    garage: [
      %{name: "Tools", icon: "hero-wrench-screwdriver", sort_order: 0},
      %{name: "Automotive", icon: "hero-truck", sort_order: 1},
      %{name: "Cleaning Supplies", icon: "hero-sparkles", sort_order: 2},
      %{name: "Hardware", icon: "hero-cog-6-tooth", sort_order: 3},
      %{name: "Paint & Supplies", icon: "hero-swatch", sort_order: 4},
      %{name: "Outdoor/Garden", icon: "hero-sun", sort_order: 5}
    ],
    bulk_storage: [
      %{name: "Paper Products", icon: "hero-document", sort_order: 0},
      %{name: "Canned Goods", icon: "hero-archive-box", sort_order: 1},
      %{name: "Cleaning Supplies", icon: "hero-sparkles", sort_order: 2},
      %{name: "Personal Care", icon: "hero-heart", sort_order: 3},
      %{name: "Beverages", icon: "hero-beaker", sort_order: 4}
    ],
    pet_supplies: [
      %{name: "Food & Treats", icon: "hero-cake", sort_order: 0},
      %{name: "Medications", icon: "hero-heart", sort_order: 1},
      %{name: "Toys & Accessories", icon: "hero-gift", sort_order: 2},
      %{name: "Grooming", icon: "hero-sparkles", sort_order: 3}
    ],
    garden_shed: [
      %{name: "Hand Tools", icon: "hero-wrench-screwdriver", sort_order: 0},
      %{name: "Seeds & Bulbs", icon: "hero-leaf", sort_order: 1},
      %{name: "Fertilizers & Soil", icon: "hero-beaker", sort_order: 2},
      %{name: "Pots & Planters", icon: "hero-archive-box", sort_order: 3},
      %{name: "Pest Control", icon: "hero-shield-check", sort_order: 4}
    ]
  }

  def category_templates, do: @category_templates

  @doc """
  Suggests a category template key based on the location name.
  """
  def suggest_template(name) do
    downcased = String.downcase(name)

    cond do
      String.contains?(downcased, "pantry") -> :pantry
      String.contains?(downcased, "garage") -> :garage
      String.contains?(downcased, "bulk") -> :bulk_storage
      String.contains?(downcased, "pet") -> :pet_supplies
      String.contains?(downcased, "garden") or String.contains?(downcased, "shed") -> :garden_shed
      true -> nil
    end
  end

  # =============================================================================
  # Storage Locations
  # =============================================================================

  @doc """
  Lists all storage locations for a household, ordered by sort_order then name.
  """
  def list_storage_locations(household_id) do
    StorageLocation
    |> where([l], l.household_id == ^household_id)
    |> order_by([l], asc: l.sort_order, asc: l.name)
    |> Repo.all()
  end

  @doc """
  Gets a storage location by ID.
  """
  def get_storage_location(id), do: Repo.get(StorageLocation, id)

  @doc """
  Gets a storage location by ID, ensuring it belongs to the household.
  """
  def get_storage_location(id, household_id) do
    StorageLocation
    |> where([l], l.id == ^id and l.household_id == ^household_id)
    |> Repo.one()
  end

  @doc """
  Gets the default "On Hand" catch-all storage location for a household.
  """
  def get_default_storage_location(household_id) do
    StorageLocation
    |> where([l], l.household_id == ^household_id and l.is_default == true)
    |> Repo.one()
  end

  @doc """
  Gets the "Pantry" storage location for a household.
  """
  def get_pantry_location(household_id) do
    StorageLocation
    |> where(
      [l],
      l.household_id == ^household_id and l.name == "Pantry" and l.is_default == false
    )
    |> Repo.one()
  end

  @doc """
  Creates a storage location. Pass `template: :pantry` (or other key) in opts
  to auto-create categories from a template.
  """
  def create_storage_location(attrs, opts \\ []) do
    result =
      %StorageLocation{}
      |> StorageLocation.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, location} ->
        template = Keyword.get(opts, :template)

        if template do
          create_default_categories(location.id, location.household_id, template)
        end

        broadcast(:pantry, location.household_id, {:storage_location_created, location})
        {:ok, location}

      error ->
        error
    end
  end

  @doc """
  Updates a storage location.
  """
  def update_storage_location(%StorageLocation{} = location, attrs) do
    location
    |> StorageLocation.changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        broadcast(:pantry, updated.household_id, {:storage_location_updated, updated})

      _ ->
        :ok
    end)
  end

  @doc """
  Deletes a non-default storage location. Moves its items to the "On Hand"
  catch-all location (nilifying their category_id since categories are
  location-scoped). Categories are cascade-deleted by the DB.
  """
  def delete_storage_location(%StorageLocation{is_default: true}),
    do: {:error, :cannot_delete_default}

  def delete_storage_location(%StorageLocation{} = location) do
    default = get_default_storage_location(location.household_id)

    Repo.transaction(fn ->
      # Move items to default location, clear category
      Item
      |> where([i], i.storage_location_id == ^location.id)
      |> Repo.update_all(set: [storage_location_id: default.id, category_id: nil])

      case Repo.delete(location) do
        {:ok, deleted} ->
          broadcast(:pantry, deleted.household_id, {:storage_location_deleted, deleted})
          deleted

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Reorders storage locations by setting their sort_order.
  """
  def reorder_storage_locations(household_id, location_ids) do
    Repo.transaction(fn ->
      location_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        StorageLocation
        |> where([l], l.id == ^id and l.household_id == ^household_id)
        |> Repo.update_all(set: [sort_order: index])
      end)
    end)
  end

  @doc """
  Creates the default "On Hand" + "Pantry" locations for a new household.
  Returns {on_hand, pantry}.
  """
  def create_default_locations(household_id) do
    {:ok, on_hand} =
      create_storage_location(%{
        name: "On Hand",
        icon: "hero-inbox-stack",
        sort_order: 0,
        is_default: true,
        household_id: household_id
      })

    {:ok, pantry} =
      create_storage_location(
        %{
          name: "Pantry",
          icon: "hero-archive-box",
          sort_order: 1,
          is_default: false,
          household_id: household_id
        },
        template: :pantry
      )

    {on_hand, pantry}
  end

  @doc """
  Moves an item to a different storage location, nilifying its category
  since categories are scoped to locations.
  """
  def move_item_to_location(%Item{} = item, storage_location_id) do
    update_item(item, %{storage_location_id: storage_location_id, category_id: nil})
  end

  # =============================================================================
  # Categories
  # =============================================================================

  @doc """
  Lists all categories for a storage location, ordered by sort_order.
  """
  def list_categories(storage_location_id) do
    Category
    |> where([c], c.storage_location_id == ^storage_location_id)
    |> order_by([c], asc: c.sort_order, asc: c.name)
    |> Repo.all()
  end

  @doc """
  Lists all categories for a household (across all locations).
  """
  def list_all_categories(household_id) do
    Category
    |> where([c], c.household_id == ^household_id)
    |> order_by([c], asc: c.sort_order, asc: c.name)
    |> Repo.all()
  end

  @doc """
  Gets a category by ID.
  """
  def get_category(id), do: Repo.get(Category, id)

  @doc """
  Gets a category by ID, ensuring it belongs to the household.
  """
  def get_category(id, household_id) do
    Category
    |> where([c], c.id == ^id and c.household_id == ^household_id)
    |> Repo.one()
  end

  @doc """
  Creates a category.
  """
  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
    |> broadcast_change(:category_created)
  end

  @doc """
  Updates a category.
  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
    |> broadcast_change(:category_updated)
  end

  @doc """
  Deletes a category.
  """
  def delete_category(%Category{} = category) do
    result = Repo.delete(category)
    broadcast_change(result, :category_deleted)
    result
  end

  @doc """
  Reorders categories by setting their sort_order.
  """
  def reorder_categories(household_id, category_ids) do
    Repo.transaction(fn ->
      category_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        Category
        |> where([c], c.id == ^id and c.household_id == ^household_id)
        |> Repo.update_all(set: [sort_order: index])
      end)
    end)
    |> case do
      {:ok, _} ->
        broadcast(:pantry, household_id, :categories_reordered)
        :ok

      error ->
        error
    end
  end

  @doc """
  Gets a category by name within a storage location.
  """
  def get_category_by_name(storage_location_id, name) do
    Category
    |> where([c], c.storage_location_id == ^storage_location_id and c.name == ^name)
    |> Repo.one()
  end

  @doc """
  Finds or creates a category by name within a storage location.
  Requires household_id for the category record.
  """
  def find_or_create_category(storage_location_id, name) do
    location = get_storage_location(storage_location_id)

    case get_category_by_name(storage_location_id, name) do
      nil ->
        create_category(%{
          name: name,
          household_id: location.household_id,
          storage_location_id: storage_location_id
        })

      category ->
        {:ok, category}
    end
  end

  @doc """
  Creates default categories for a storage location from a template.
  """
  def create_default_categories(storage_location_id, household_id, template \\ :pantry) do
    categories = Map.get(@category_templates, template, @category_templates[:pantry])

    Enum.each(categories, fn attrs ->
      create_category(
        Map.merge(attrs, %{
          household_id: household_id,
          storage_location_id: storage_location_id
        })
      )
    end)
  end

  # =============================================================================
  # Items
  # =============================================================================

  @doc """
  Lists all items for a household, with optional filtering.

  ## Options
    * `:storage_location_id` - scope to a specific storage location
    * `:category_id` - filter by category (or `:uncategorized`)
    * `:needs_restock` - when true, only return items needing restock
    * `:order_by` - `:name`, `:expiration`, or `:quantity`
  """
  def list_items(household_id, opts \\ []) do
    query =
      Item
      |> where([i], i.household_id == ^household_id)
      |> preload(:category)

    query =
      case Keyword.get(opts, :storage_location_id) do
        nil -> query
        id -> where(query, [i], i.storage_location_id == ^id)
      end

    query =
      case Keyword.get(opts, :category_id) do
        nil -> query
        :uncategorized -> where(query, [i], is_nil(i.category_id))
        id -> where(query, [i], i.category_id == ^id)
      end

    query =
      case Keyword.get(opts, :needs_restock) do
        true ->
          where(
            query,
            [i],
            i.always_in_stock == true and i.quantity <= coalesce(i.restock_threshold, 0)
          )

        _ ->
          query
      end

    query =
      case Keyword.get(opts, :order_by) do
        :name -> order_by(query, [i], asc: i.name)
        :expiration -> order_by(query, [i], asc_nulls_last: i.expiration_date)
        :quantity -> order_by(query, [i], asc: i.quantity)
        _ -> order_by(query, [i], asc: i.name)
      end

    Repo.all(query)
  end

  @doc """
  Gets an item by ID.
  """
  def get_item(id), do: Repo.get(Item, id) |> Repo.preload(:category)

  @doc """
  Gets an item by ID, ensuring it belongs to the household.
  """
  def get_item(id, household_id) do
    Item
    |> where([i], i.id == ^id and i.household_id == ^household_id)
    |> preload(:category)
    |> Repo.one()
  end

  @doc """
  Finds an item by name (case-insensitive) within a household.
  """
  def find_item_by_name(name, household_id) do
    Item
    |> where(
      [i],
      i.household_id == ^household_id and fragment("LOWER(?)", i.name) == ^String.downcase(name)
    )
    |> preload(:category)
    |> Repo.one()
  end

  @doc """
  Gets an item by barcode.
  """
  def get_item_by_barcode(barcode, household_id) do
    Item
    |> where([i], i.barcode == ^barcode and i.household_id == ^household_id)
    |> preload(:category)
    |> Repo.one()
  end

  @doc """
  Creates an item.
  """
  def create_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
    |> broadcast_change(:item_created)
  end

  @doc """
  Creates an item with user tracking.
  """
  def create_item(attrs, _user) do
    create_item(attrs)
  end

  @doc """
  Updates just the nutrition data on a pantry item.
  """
  def update_item_nutrition(%Item{} = item, nutrition_attrs) do
    item
    |> Item.nutrition_changeset(%{nutrition: nutrition_attrs})
    |> Repo.update()
    |> broadcast_change(:item_updated)
  end

  @doc """
  Updates an item.
  """
  def update_item(%Item{} = item, attrs) do
    item
    |> Item.changeset(attrs)
    |> Repo.update()
    |> broadcast_change(:item_updated)
  end

  @doc """
  Deletes an item.
  """
  def delete_item(%Item{} = item) do
    result = Repo.delete(item)
    broadcast_change(result, :item_deleted)
    result
  end

  @doc """
  Adjusts the quantity of an item and creates a transaction.
  """
  def adjust_quantity(%Item{} = item, change, user, opts \\ []) do
    action = Keyword.get(opts, :action, :adjust)
    reason = Keyword.get(opts, :reason)
    notes = Keyword.get(opts, :notes)

    quantity_before = item.quantity
    quantity_after = Decimal.add(item.quantity, change)

    quantity_after =
      if Decimal.compare(quantity_after, Decimal.new(0)) == :lt do
        Decimal.new(0)
      else
        quantity_after
      end

    Repo.transaction(fn ->
      {:ok, updated_item} = update_item(item, %{quantity: quantity_after})

      {:ok, _transaction} =
        create_transaction(%{
          action: action,
          quantity_change: change,
          quantity_before: quantity_before,
          quantity_after: quantity_after,
          reason: reason,
          notes: notes,
          pantry_item_id: item.id,
          user_id: user && user.id
        })

      if Item.needs_restock?(updated_item) do
        broadcast(:pantry, item.household_id, {:restock_needed, updated_item})
      end

      if not item.always_in_stock and
           Decimal.compare(quantity_after, Decimal.new(0)) == :eq and
           Decimal.compare(quantity_before, Decimal.new(0)) == :gt do
        broadcast(:pantry, item.household_id, {:item_depleted, updated_item})
      end

      updated_item
    end)
  end

  @doc """
  Adds quantity to an item.
  """
  def add_to_item(%Item{} = item, amount, user, opts \\ []) do
    adjust_quantity(item, to_decimal(amount), user, Keyword.put(opts, :action, :add))
  end

  @doc """
  Removes quantity from an item.
  """
  def remove_from_item(%Item{} = item, amount, user, opts \\ []) do
    adjust_quantity(
      item,
      Decimal.negate(to_decimal(amount)),
      user,
      Keyword.put(opts, :action, :remove)
    )
  end

  @doc """
  Uses quantity from an item (e.g., when cooking).
  """
  def use_item(%Item{} = item, amount, user, opts \\ []) do
    adjust_quantity(
      item,
      Decimal.negate(to_decimal(amount)),
      user,
      Keyword.put(opts, :action, :use)
    )
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(amount) when is_float(amount), do: Decimal.from_float(amount)
  defp to_decimal(amount), do: Decimal.new(amount)

  @doc """
  Returns items that need restocking.
  """
  def items_needing_restock(household_id) do
    list_items(household_id, needs_restock: true)
  end

  @doc """
  Alias for items_needing_restock with a shorter name.
  """
  def list_items_needing_restock(household_id) do
    items_needing_restock(household_id)
  end

  @doc """
  Checks if an item needs restocking.
  """
  def needs_restock?(%Item{} = item) do
    Item.needs_restock?(item)
  end

  @doc """
  Returns items expiring soon.
  """
  def items_expiring_soon(household_id, days \\ 7) do
    cutoff_date = Date.add(Date.utc_today(), days)

    Item
    |> where([i], i.household_id == ^household_id)
    |> where([i], not is_nil(i.expiration_date))
    |> where([i], i.expiration_date <= ^cutoff_date)
    |> where([i], i.expiration_date >= ^Date.utc_today())
    |> order_by([i], asc: i.expiration_date)
    |> preload(:category)
    |> Repo.all()
  end

  @doc """
  Returns expired items.
  """
  def expired_items(household_id) do
    Item
    |> where([i], i.household_id == ^household_id)
    |> where([i], not is_nil(i.expiration_date))
    |> where([i], i.expiration_date < ^Date.utc_today())
    |> order_by([i], asc: i.expiration_date)
    |> preload(:category)
    |> Repo.all()
  end

  @doc """
  Searches items by name, optionally scoped to a storage location.
  """
  def search_items(household_id, query, opts \\ []) do
    search_term = "%#{query}%"

    db_query =
      Item
      |> where([i], i.household_id == ^household_id)
      |> where([i], ilike(i.name, ^search_term))
      |> order_by([i], asc: i.name)
      |> preload(:category)

    db_query =
      case Keyword.get(opts, :storage_location_id) do
        nil -> db_query
        id -> where(db_query, [i], i.storage_location_id == ^id)
      end

    Repo.all(db_query)
  end

  # =============================================================================
  # Transactions
  # =============================================================================

  @doc """
  Creates a transaction.
  """
  def create_transaction(attrs) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists transactions for an item.
  """
  def list_transactions_for_item(item_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Transaction
    |> where([t], t.pantry_item_id == ^item_id)
    |> order_by([t], desc: t.inserted_at)
    |> limit(^limit)
    |> preload(:user)
    |> Repo.all()
  end

  # =============================================================================
  # PubSub
  # =============================================================================

  @doc """
  Subscribes to pantry updates for a household.
  """
  def subscribe(household_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(household_id))
  end

  defp topic(household_id), do: "pantry:#{household_id}"

  defp broadcast_change({:ok, record}, event) do
    case record do
      %Item{} = item ->
        broadcast(:pantry, item.household_id, {event, item})

      %Category{} = category ->
        broadcast(:pantry, category.household_id, {event, category})

      _ ->
        :ok
    end

    {:ok, record}
  end

  defp broadcast_change({:error, _} = error, _event), do: error

  defp broadcast(:pantry, household_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic(household_id), message)
  end
end
