defmodule FeedMe.Pantry do
  @moduledoc """
  The Pantry context manages inventory, categories, and transactions.
  """

  import Ecto.Query, warn: false
  alias FeedMe.Pantry.{Category, Item, Transaction}
  alias FeedMe.Repo

  @pubsub FeedMe.PubSub

  # =============================================================================
  # Categories
  # =============================================================================

  @doc """
  Lists all categories for a household, ordered by sort_order.
  """
  def list_categories(household_id) do
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
  Gets a category by name for a household.
  """
  def get_category_by_name(household_id, name) do
    Category
    |> where([c], c.household_id == ^household_id and c.name == ^name)
    |> Repo.one()
  end

  @doc """
  Finds or creates a category by name.
  """
  def find_or_create_category(household_id, name) do
    case get_category_by_name(household_id, name) do
      nil -> create_category(%{name: name, household_id: household_id})
      category -> {:ok, category}
    end
  end

  @doc """
  Creates default categories for a new household.
  """
  def create_default_categories(household_id) do
    default_categories = [
      %{name: "Produce", icon: "hero-leaf", sort_order: 0},
      %{name: "Dairy", icon: "hero-beaker", sort_order: 1},
      %{name: "Meat & Seafood", icon: "hero-fire", sort_order: 2},
      %{name: "Pantry Staples", icon: "hero-archive-box", sort_order: 3},
      %{name: "Frozen", icon: "hero-cube", sort_order: 4},
      %{name: "Beverages", icon: "hero-beaker", sort_order: 5},
      %{name: "Snacks", icon: "hero-cake", sort_order: 6},
      %{name: "Condiments", icon: "hero-adjustments-horizontal", sort_order: 7}
    ]

    Enum.each(default_categories, fn attrs ->
      create_category(Map.put(attrs, :household_id, household_id))
    end)
  end

  # =============================================================================
  # Items
  # =============================================================================

  @doc """
  Lists all items for a household.
  """
  def list_items(household_id, opts \\ []) do
    query =
      Item
      |> where([i], i.household_id == ^household_id)
      |> preload(:category)

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
    # User tracking could be added here if needed
    create_item(attrs)
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

    # Ensure quantity doesn't go negative
    quantity_after =
      if Decimal.compare(quantity_after, Decimal.new(0)) == :lt do
        Decimal.new(0)
      else
        quantity_after
      end

    Repo.transaction(fn ->
      # Update item quantity
      {:ok, updated_item} = update_item(item, %{quantity: quantity_after})

      # Create transaction record
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

      # Check if item needs restocking
      if Item.needs_restock?(updated_item) do
        broadcast(:pantry, item.household_id, {:restock_needed, updated_item})
      end

      updated_item
    end)
  end

  @doc """
  Adds quantity to an item.
  """
  def add_to_item(%Item{} = item, amount, user, opts \\ []) do
    adjust_quantity(item, Decimal.new(amount), user, Keyword.put(opts, :action, :add))
  end

  @doc """
  Removes quantity from an item.
  """
  def remove_from_item(%Item{} = item, amount, user, opts \\ []) do
    adjust_quantity(
      item,
      Decimal.negate(Decimal.new(amount)),
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
      Decimal.negate(Decimal.new(amount)),
      user,
      Keyword.put(opts, :action, :use)
    )
  end

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
  Searches items by name.
  """
  def search_items(household_id, query) do
    search_term = "%#{query}%"

    Item
    |> where([i], i.household_id == ^household_id)
    |> where([i], ilike(i.name, ^search_term))
    |> order_by([i], asc: i.name)
    |> preload(:category)
    |> Repo.all()
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
