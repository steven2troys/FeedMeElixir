defmodule FeedMeWeb.ShoppingListChannel do
  use FeedMeWeb, :channel

  alias FeedMe.Accounts
  alias FeedMe.Households
  alias FeedMe.Shopping

  @impl true
  def join("shopping_list:" <> list_id, _payload, socket) do
    user_id = socket.assigns.user_id
    list = Shopping.get_list(list_id)
    user = Accounts.get_user!(user_id)

    cond do
      list == nil ->
        {:error, %{reason: "list_not_found"}}

      !Households.member?(user, list.household_id) ->
        {:error, %{reason: "unauthorized"}}

      true ->
        send(self(), :after_join)
        {:ok, assign(socket, :list_id, list_id)}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    items = Shopping.list_items(socket.assigns.list_id)

    push(socket, "items_sync", %{
      items: Enum.map(items, &serialize_item/1)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("add_item", %{"name" => name} = params, socket) do
    attrs = %{
      name: name,
      quantity: params["quantity"] || 1,
      unit: params["unit"],
      shopping_list_id: socket.assigns.list_id,
      added_by_id: socket.assigns.user_id,
      category_id: params["category_id"]
    }

    case Shopping.create_item(attrs) do
      {:ok, item} ->
        broadcast!(socket, "item_added", %{item: serialize_item(item)})
        {:reply, :ok, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end

  def handle_in("update_item", %{"id" => id} = params, socket) do
    item = Shopping.get_item(id)

    if item && item.shopping_list_id == socket.assigns.list_id do
      attrs =
        params
        |> Map.take(["name", "quantity", "unit", "notes", "aisle_location", "sort_order"])
        |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

      case Shopping.update_item(item, attrs) do
        {:ok, updated} ->
          broadcast!(socket, "item_updated", %{item: serialize_item(updated)})
          {:reply, :ok, socket}

        {:error, changeset} ->
          {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
      end
    else
      {:reply, {:error, %{reason: "item_not_found"}}, socket}
    end
  end

  def handle_in("toggle_item", %{"id" => id}, socket) do
    item = Shopping.get_item(id)

    if item && item.shopping_list_id == socket.assigns.list_id do
      case Shopping.toggle_item_checked(item, socket.assigns.user_id) do
        {:ok, updated} ->
          broadcast!(socket, "item_toggled", %{item: serialize_item(updated)})
          {:reply, :ok, socket}

        {:error, changeset} ->
          {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
      end
    else
      {:reply, {:error, %{reason: "item_not_found"}}, socket}
    end
  end

  def handle_in("delete_item", %{"id" => id}, socket) do
    item = Shopping.get_item(id)

    if item && item.shopping_list_id == socket.assigns.list_id do
      case Shopping.delete_item(item) do
        {:ok, _} ->
          broadcast!(socket, "item_deleted", %{id: id})
          {:reply, :ok, socket}

        {:error, _} ->
          {:reply, {:error, %{reason: "delete_failed"}}, socket}
      end
    else
      {:reply, {:error, %{reason: "item_not_found"}}, socket}
    end
  end

  def handle_in("clear_checked", _params, socket) do
    list = Shopping.get_list(socket.assigns.list_id)

    case Shopping.clear_checked_items(list) do
      {:ok, count} ->
        broadcast!(socket, "checked_cleared", %{count: count})
        {:reply, :ok, socket}

      _ ->
        {:reply, {:error, %{reason: "clear_failed"}}, socket}
    end
  end

  def handle_in("reorder_items", %{"item_ids" => item_ids}, socket) do
    Enum.with_index(item_ids)
    |> Enum.each(fn {id, index} ->
      item = Shopping.get_item(id)

      if item && item.shopping_list_id == socket.assigns.list_id do
        Shopping.update_item(item, %{sort_order: index})
      end
    end)

    broadcast!(socket, "items_reordered", %{item_ids: item_ids})
    {:reply, :ok, socket}
  end

  defp serialize_item(item) do
    %{
      id: item.id,
      name: item.name,
      quantity: Decimal.to_string(item.quantity),
      unit: item.unit,
      checked: item.checked,
      checked_at: item.checked_at,
      aisle_location: item.aisle_location,
      notes: item.notes,
      sort_order: item.sort_order,
      category_id: item.category_id,
      category_name: item.category && item.category.name,
      pantry_item_id: item.pantry_item_id
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
