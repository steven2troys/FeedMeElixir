defmodule FeedMeWeb.ShoppingLive.Show do
  use FeedMeWeb, :live_view

  alias FeedMe.Households
  alias FeedMe.Pantry
  alias FeedMe.Shopping

  @impl true
  def mount(%{"household_id" => household_id, "id" => list_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Households.get_household_for_user(household_id, user) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Household not found")
         |> push_navigate(to: ~p"/households")}

      %{household: household} ->
        list = Shopping.get_list_with_items(list_id, household.id)

        if list do
          if connected?(socket), do: Shopping.subscribe(household.id)

          categories = Pantry.list_categories(household.id)
          # Generate socket token for channel
          token = Phoenix.Token.sign(FeedMeWeb.Endpoint, "user socket", user.id)

          {:ok,
           socket
           |> assign(:household, household)
           |> assign(:list, list)
           |> assign(:categories, categories)
           |> assign(:socket_token, token)
           |> assign(:new_item_name, "")
           |> assign(:page_title, list.name)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Shopping list not found")
           |> push_navigate(to: ~p"/households/#{household.id}/shopping")}
        end
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_item", %{"name" => name}, socket) when name != "" do
    user = socket.assigns.current_scope.user

    attrs = %{
      name: name,
      shopping_list_id: socket.assigns.list.id,
      added_by_id: user.id
    }

    case Shopping.create_item(attrs) do
      {:ok, _item} ->
        list = Shopping.get_list_with_items(socket.assigns.list.id, socket.assigns.household.id)
        {:noreply, assign(socket, list: list, new_item_name: "")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add item")}
    end
  end

  def handle_event("add_item", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_item", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    item = Shopping.get_item(id)

    if item && item.shopping_list_id == socket.assigns.list.id do
      {:ok, _} = Shopping.toggle_item_checked(item, user.id)
      list = Shopping.get_list_with_items(socket.assigns.list.id, socket.assigns.household.id)
      {:noreply, assign(socket, list: list)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Shopping.get_item(id)

    if item && item.shopping_list_id == socket.assigns.list.id do
      {:ok, _} = Shopping.delete_item(item)
      list = Shopping.get_list_with_items(socket.assigns.list.id, socket.assigns.household.id)
      {:noreply, assign(socket, list: list)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_checked", _params, socket) do
    {:ok, _} = Shopping.clear_checked_items(socket.assigns.list)
    list = Shopping.get_list_with_items(socket.assigns.list.id, socket.assigns.household.id)
    {:noreply, assign(socket, list: list)}
  end

  def handle_event("transfer_to_pantry", _params, socket) do
    user = socket.assigns.current_scope.user
    Shopping.transfer_checked_to_pantry(socket.assigns.list, user)
    list = Shopping.get_list_with_items(socket.assigns.list.id, socket.assigns.household.id)

    {:noreply,
     socket
     |> put_flash(:info, "Checked items added to pantry")
     |> assign(:list, list)}
  end

  @impl true
  def handle_info({:item_created, _item}, socket) do
    list = Shopping.get_list_with_items(socket.assigns.list.id, socket.assigns.household.id)
    {:noreply, assign(socket, list: list)}
  end

  def handle_info({:item_updated, _item}, socket) do
    list = Shopping.get_list_with_items(socket.assigns.list.id, socket.assigns.household.id)
    {:noreply, assign(socket, list: list)}
  end

  def handle_info({:item_toggled, _item}, socket) do
    list = Shopping.get_list_with_items(socket.assigns.list.id, socket.assigns.household.id)
    {:noreply, assign(socket, list: list)}
  end

  def handle_info({:item_deleted, _item}, socket) do
    list = Shopping.get_list_with_items(socket.assigns.list.id, socket.assigns.household.id)
    {:noreply, assign(socket, list: list)}
  end

  def handle_info(:items_cleared, socket) do
    list = Shopping.get_list_with_items(socket.assigns.list.id, socket.assigns.household.id)
    {:noreply, assign(socket, list: list)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    unchecked = Enum.reject(assigns.list.items, & &1.checked)
    checked = Enum.filter(assigns.list.items, & &1.checked)
    assigns = assign(assigns, unchecked: unchecked, checked: checked)

    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        <%= @list.name %>
        <:subtitle>
          <%= length(@unchecked) %> items remaining
          <%= if length(@checked) > 0 do %>
            · <%= length(@checked) %> checked
          <% end %>
        </:subtitle>
        <:actions>
          <%= if length(@checked) > 0 do %>
            <div class="dropdown dropdown-end">
              <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
                <.icon name="hero-ellipsis-vertical" class="size-5" />
              </div>
              <ul tabindex="0" class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52">
                <li>
                  <button phx-click="transfer_to_pantry">
                    <.icon name="hero-arrow-up-tray" class="size-4" /> Add to Pantry
                  </button>
                </li>
                <li>
                  <button phx-click="clear_checked" class="text-error">
                    <.icon name="hero-trash" class="size-4" /> Clear Checked
                  </button>
                </li>
              </ul>
            </div>
          <% end %>
        </:actions>
      </.header>

      <div class="mt-6">
        <form phx-submit="add_item" class="flex gap-2">
          <input
            type="text"
            name="name"
            value={@new_item_name}
            placeholder="Add an item..."
            class="input input-bordered flex-1"
            autocomplete="off"
          />
          <button type="submit" class="btn btn-primary">Add</button>
        </form>
      </div>

      <div class="mt-6 space-y-2">
        <%= for item <- @unchecked do %>
          <div class="card bg-base-100 shadow-sm border border-base-200">
            <div class="card-body p-3 flex-row items-center gap-3">
              <input
                type="checkbox"
                class="checkbox checkbox-primary"
                checked={item.checked}
                phx-click="toggle_item"
                phx-value-id={item.id}
              />
              <div class="flex-1">
                <span class="font-medium"><%= item.name %></span>
                <%= if item.quantity && Decimal.compare(item.quantity, Decimal.new(1)) != :eq do %>
                  <span class="text-base-content/70 text-sm ml-2">
                    (<%= Decimal.to_string(item.quantity) %><%= if item.unit, do: " #{item.unit}" %>)
                  </span>
                <% end %>
                <%= if item.category do %>
                  <span class="badge badge-sm badge-ghost ml-2"><%= item.category.name %></span>
                <% end %>
              </div>
              <button
                phx-click="delete_item"
                phx-value-id={item.id}
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <%= if length(@checked) > 0 do %>
        <div class="mt-8">
          <h3 class="text-sm font-semibold text-base-content/70 mb-2">
            Checked (<%= length(@checked) %>)
          </h3>
          <div class="space-y-2 opacity-60">
            <%= for item <- @checked do %>
              <div class="card bg-base-200 border border-base-300">
                <div class="card-body p-3 flex-row items-center gap-3">
                  <input
                    type="checkbox"
                    class="checkbox"
                    checked={item.checked}
                    phx-click="toggle_item"
                    phx-value-id={item.id}
                  />
                  <div class="flex-1">
                    <span class="line-through"><%= item.name %></span>
                  </div>
                  <button
                    phx-click="delete_item"
                    phx-value-id={item.id}
                    class="btn btn-ghost btn-sm"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <.back navigate={~p"/households/#{@household.id}/shopping"}>Back to shopping lists</.back>
    </div>
    """
  end
end
