defmodule FeedMeWeb.RestockHooks do
  @moduledoc """
  LiveView hooks for auto-restock: adds keep-in-stock items to shopping list
  automatically, and prompts users to add depleted items.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias FeedMe.Pantry
  alias FeedMe.Shopping

  def attach_restock_hooks(socket) do
    household = socket.assigns[:household]

    if household && connected?(socket) do
      Pantry.subscribe(household.id)
    end

    socket
    |> assign(:restock_prompts, %{})
    |> assign(:on_pantry_page, false)
    |> attach_hook(:restock_info, :handle_info, &handle_info/2)
    |> attach_hook(:restock_events, :handle_event, &handle_event/3)
  end

  defp handle_info({:restock_needed, item}, socket) do
    household = socket.assigns.household
    user = socket.assigns.current_scope.user
    main_list = Shopping.get_or_create_main_list(household.id)

    if Shopping.item_on_list?(main_list.id, item.id) do
      {:halt, socket}
    else
      threshold = item.restock_threshold || Decimal.new(0)
      quantity_needed = Decimal.sub(threshold, item.quantity)

      quantity_needed =
        if Decimal.compare(quantity_needed, Decimal.new(0)) == :gt,
          do: quantity_needed,
          else: Decimal.new("1")

      case Shopping.add_from_pantry(main_list.id, item, quantity_needed, user) do
        {:ok, _shopping_item} ->
          {:halt,
           put_flash(
             socket,
             :info,
             "Added #{item.name} (\u00d7#{quantity_needed}) to shopping list"
           )}

        {:error, _reason} ->
          {:halt, socket}
      end
    end
  end

  defp handle_info({:item_depleted, item}, socket) do
    household = socket.assigns.household
    main_list = Shopping.get_or_create_main_list(household.id)

    if Shopping.item_on_list?(main_list.id, item.id) do
      {:halt, socket}
    else
      prompts =
        Map.put(socket.assigns.restock_prompts, item.id, %{
          id: item.id,
          name: item.name,
          unit: item.unit
        })

      {:halt, assign(socket, :restock_prompts, prompts)}
    end
  end

  defp handle_info(_msg, socket), do: {:cont, socket}

  defp handle_event("add_to_shopping", %{"item-id" => pantry_item_id}, socket) do
    household = socket.assigns.household
    user = socket.assigns.current_scope.user

    case Pantry.get_item(pantry_item_id, household.id) do
      nil ->
        {:halt, socket}

      pantry_item ->
        main_list = Shopping.get_or_create_main_list(household.id)

        unless Shopping.item_on_list?(main_list.id, pantry_item.id) do
          Shopping.add_from_pantry(main_list.id, pantry_item, Decimal.new("1"), user)
        end

        prompts = Map.delete(socket.assigns.restock_prompts, pantry_item_id)

        {:halt,
         socket
         |> assign(:restock_prompts, prompts)
         |> put_flash(:info, "Added #{pantry_item.name} to shopping list")}
    end
  end

  defp handle_event("dismiss_restock", %{"item-id" => pantry_item_id}, socket) do
    prompts = Map.delete(socket.assigns.restock_prompts, pantry_item_id)
    {:halt, assign(socket, :restock_prompts, prompts)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
