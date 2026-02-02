defmodule FeedMe.Shopping do
  @moduledoc """
  The Shopping context manages shopping lists and their items.
  """

  import Ecto.Query, warn: false
  alias FeedMe.Repo
  alias FeedMe.Shopping.{List, Item, CategoryOrder}
  alias FeedMe.Pantry

  @pubsub FeedMe.PubSub

  # =============================================================================
  # Lists
  # =============================================================================

  @doc """
  Lists all shopping lists for a household.
  """
  def list_shopping_lists(household_id) do
    List
    |> where([l], l.household_id == ^household_id)
    |> order_by([l], desc: l.is_main, asc: l.name)
    |> Repo.all()
  end

  @doc """
  Gets or creates the main shopping list for a household.
  """
  def get_or_create_main_list(household_id) do
    case get_main_list(household_id) do
      nil ->
        {:ok, list} = create_list(%{name: "Shopping List", is_main: true, household_id: household_id})
        list

      list ->
        list
    end
  end

  @doc """
  Gets the main shopping list for a household.
  """
  def get_main_list(household_id) do
    List
    |> where([l], l.household_id == ^household_id and l.is_main == true)
    |> Repo.one()
  end

  @doc """
  Gets a shopping list by ID.
  """
  def get_list(id), do: Repo.get(List, id)

  @doc """
  Gets a shopping list by ID, ensuring it belongs to the household.
  """
  def get_list(id, household_id) do
    List
    |> where([l], l.id == ^id and l.household_id == ^household_id)
    |> Repo.one()
  end

  @doc """
  Gets a shopping list with all items preloaded.
  """
  def get_list_with_items(id, household_id) do
    items_query =
      from i in Item,
        order_by: [asc: i.sort_order, asc: i.name],
        preload: [:category, :pantry_item]

    List
    |> where([l], l.id == ^id and l.household_id == ^household_id)
    |> preload([l], items: ^items_query)
    |> Repo.one()
  end

  @doc """
  Creates a shopping list.
  """
  def create_list(attrs) do
    %List{}
    |> List.changeset(attrs)
    |> Repo.insert()
    |> broadcast_change(:list_created)
  end

  @doc """
  Updates a shopping list.
  """
  def update_list(%List{} = list, attrs) do
    list
    |> List.changeset(attrs)
    |> Repo.update()
    |> broadcast_change(:list_updated)
  end

  @doc """
  Deletes a shopping list.
  """
  def delete_list(%List{} = list) do
    result = Repo.delete(list)
    broadcast_change(result, :list_deleted)
    result
  end

  @doc """
  Marks a list as completed.
  """
  def complete_list(%List{} = list) do
    update_list(list, %{status: :completed})
  end

  @doc """
  Archives a list.
  """
  def archive_list(%List{} = list) do
    update_list(list, %{status: :archived})
  end

  # =============================================================================
  # Items
  # =============================================================================

  @doc """
  Lists all items in a shopping list.
  """
  def list_items(shopping_list_id) do
    Item
    |> where([i], i.shopping_list_id == ^shopping_list_id)
    |> order_by([i], asc: i.sort_order, asc: i.name)
    |> preload([:category, :pantry_item])
    |> Repo.all()
  end

  @doc """
  Lists unchecked items in a shopping list.
  """
  def list_unchecked_items(shopping_list_id) do
    Item
    |> where([i], i.shopping_list_id == ^shopping_list_id and i.checked == false)
    |> order_by([i], asc: i.sort_order, asc: i.name)
    |> preload([:category, :pantry_item])
    |> Repo.all()
  end

  @doc """
  Gets an item by ID.
  """
  def get_item(id), do: Repo.get(Item, id) |> Repo.preload([:category, :pantry_item, :shopping_list])

  @doc """
  Creates an item.
  """
  def create_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
    |> tap(fn result ->
      case result do
        {:ok, item} ->
          item = Repo.preload(item, :shopping_list)
          broadcast(:shopping, item.shopping_list.household_id, {:item_created, item})

        _ ->
          :ok
      end
    end)
  end

  @doc """
  Updates an item.
  """
  def update_item(%Item{} = item, attrs) do
    item
    |> Item.changeset(attrs)
    |> Repo.update()
    |> tap(fn result ->
      case result do
        {:ok, updated} ->
          updated = Repo.preload(updated, :shopping_list)
          broadcast(:shopping, updated.shopping_list.household_id, {:item_updated, updated})

        _ ->
          :ok
      end
    end)
  end

  @doc """
  Deletes an item.
  """
  def delete_item(%Item{} = item) do
    item = Repo.preload(item, :shopping_list)
    result = Repo.delete(item)

    case result do
      {:ok, _} ->
        broadcast(:shopping, item.shopping_list.household_id, {:item_deleted, item})

      _ ->
        :ok
    end

    result
  end

  @doc """
  Toggles the checked status of an item.
  """
  def toggle_item_checked(%Item{} = item, user_id) do
    item
    |> Item.toggle_checked_changeset(user_id)
    |> Repo.update()
    |> tap(fn result ->
      case result do
        {:ok, updated} ->
          updated = Repo.preload(updated, :shopping_list)
          broadcast(:shopping, updated.shopping_list.household_id, {:item_toggled, updated})

        _ ->
          :ok
      end
    end)
  end

  @doc """
  Adds an item from the pantry to a shopping list.
  """
  def add_from_pantry(shopping_list_id, pantry_item, quantity, user) do
    create_item(%{
      name: pantry_item.name,
      quantity: quantity,
      unit: pantry_item.unit,
      shopping_list_id: shopping_list_id,
      pantry_item_id: pantry_item.id,
      category_id: pantry_item.category_id,
      added_by_id: user.id
    })
  end

  @doc """
  Adds items that need restocking to the main shopping list.
  """
  def add_restock_items_to_main_list(household_id, user) do
    main_list = get_or_create_main_list(household_id)
    items_to_restock = Pantry.items_needing_restock(household_id)

    # Get existing pantry item IDs in the list
    existing_pantry_ids =
      Item
      |> where([i], i.shopping_list_id == ^main_list.id)
      |> where([i], not is_nil(i.pantry_item_id))
      |> select([i], i.pantry_item_id)
      |> Repo.all()
      |> MapSet.new()

    # Add only items not already in the list
    Enum.each(items_to_restock, fn pantry_item ->
      unless MapSet.member?(existing_pantry_ids, pantry_item.id) do
        # Calculate quantity to add (threshold - current quantity)
        threshold = pantry_item.restock_threshold || Decimal.new(0)
        quantity_needed = Decimal.sub(threshold, pantry_item.quantity)

        if Decimal.compare(quantity_needed, Decimal.new(0)) == :gt do
          add_from_pantry(main_list.id, pantry_item, quantity_needed, user)
        end
      end
    end)

    main_list
  end

  @doc """
  Transfers checked items back to pantry (adds quantity to pantry items).
  """
  def transfer_checked_to_pantry(%List{} = list, user) do
    items =
      Item
      |> where([i], i.shopping_list_id == ^list.id and i.checked == true)
      |> where([i], not is_nil(i.pantry_item_id))
      |> preload(:pantry_item)
      |> Repo.all()

    Enum.each(items, fn item ->
      Pantry.add_to_item(item.pantry_item, item.quantity, user, reason: "Added from shopping list")
    end)

    # Clear checked items
    Item
    |> where([i], i.shopping_list_id == ^list.id and i.checked == true)
    |> Repo.delete_all()

    broadcast(:shopping, list.household_id, :items_cleared)

    :ok
  end

  @doc """
  Clears all checked items from a list.
  """
  def clear_checked_items(%List{} = list) do
    {count, _} =
      Item
      |> where([i], i.shopping_list_id == ^list.id and i.checked == true)
      |> Repo.delete_all()

    broadcast(:shopping, list.household_id, :items_cleared)

    {:ok, count}
  end

  # =============================================================================
  # Category Orders
  # =============================================================================

  @doc """
  Gets category orders for a household.
  """
  def get_category_orders(household_id) do
    CategoryOrder
    |> where([o], o.household_id == ^household_id)
    |> order_by([o], asc: o.sort_order)
    |> preload(:category)
    |> Repo.all()
  end

  @doc """
  Sets the category order for shopping.
  """
  def set_category_order(household_id, category_id, sort_order) do
    %CategoryOrder{}
    |> CategoryOrder.changeset(%{
      household_id: household_id,
      category_id: category_id,
      sort_order: sort_order
    })
    |> Repo.insert(
      on_conflict: {:replace, [:sort_order, :updated_at]},
      conflict_target: [:household_id, :category_id]
    )
  end

  @doc """
  Reorders categories for shopping.
  """
  def reorder_shopping_categories(household_id, category_ids) do
    Repo.transaction(fn ->
      category_ids
      |> Enum.with_index()
      |> Enum.each(fn {category_id, index} ->
        set_category_order(household_id, category_id, index)
      end)
    end)
  end

  # =============================================================================
  # PubSub
  # =============================================================================

  @doc """
  Subscribes to shopping list updates for a household.
  """
  def subscribe(household_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(household_id))
  end

  @doc """
  Subscribes to updates for a specific shopping list.
  """
  def subscribe_to_list(list_id) do
    Phoenix.PubSub.subscribe(@pubsub, list_topic(list_id))
  end

  defp topic(household_id), do: "shopping:#{household_id}"
  defp list_topic(list_id), do: "shopping_list:#{list_id}"

  defp broadcast_change({:ok, record}, event) do
    case record do
      %List{} = list ->
        broadcast(:shopping, list.household_id, {event, list})

      _ ->
        :ok
    end

    {:ok, record}
  end

  defp broadcast_change({:error, _} = error, _event), do: error

  defp broadcast(:shopping, household_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic(household_id), message)
  end
end
