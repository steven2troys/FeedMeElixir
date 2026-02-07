defmodule FeedMeWeb.ShoppingLive.Show do
  use FeedMeWeb, :live_view

  alias FeedMe.Households
  alias FeedMe.Pantry
  alias FeedMe.Shopping

  @impl true
  def mount(%{"id" => list_id}, _session, socket) do
    # household and role are set by HouseholdHooks
    user = socket.assigns.current_scope.user
    household = socket.assigns.household

    cond do
      not Shopping.list_accessible?(list_id, user.id) ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have access to this list")
         |> push_navigate(to: ~p"/households/#{household.id}/shopping")}

      true ->
        list = Shopping.get_list_with_items(list_id, household.id)

        if list do
          if connected?(socket), do: Shopping.subscribe(household.id)

          is_owner = is_nil(list.created_by_id) or list.created_by_id == user.id
          categories = Pantry.list_categories(household.id)
          token = Phoenix.Token.sign(FeedMeWeb.Endpoint, "user socket", user.id)

          {:ok,
           socket
           |> assign(:active_tab, :shopping)
           |> assign(:list, list)
           |> assign(:is_owner, is_owner)
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
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :share) do
    if socket.assigns.is_owner do
      household = socket.assigns.household
      list = socket.assigns.list
      members = Households.list_members(household.id)
      current_user = socket.assigns.current_scope.user

      other_members = Enum.reject(members, fn m -> m.user.id == current_user.id end)

      shares = Shopping.list_shares(list.id)
      shared_user_ids = MapSet.new(shares, fn s -> s.user_id end)

      socket
      |> assign(:members, other_members)
      |> assign(:shared_user_ids, shared_user_ids)
    else
      socket
      |> put_flash(:error, "Only the list owner can manage sharing")
      |> push_patch(
        to: ~p"/households/#{socket.assigns.household.id}/shopping/#{socket.assigns.list.id}"
      )
    end
  end

  defp apply_action(socket, _action), do: socket

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

  def handle_event("toggle_add_to_pantry", _params, socket) do
    list = socket.assigns.list
    new_value = !list.add_to_pantry

    case Shopping.update_list(list, %{add_to_pantry: new_value}) do
      {:ok, _updated} ->
        list = Shopping.get_list_with_items(list.id, socket.assigns.household.id)
        {:noreply, assign(socket, list: list)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update setting")}
    end
  end

  def handle_event("save_shares", %{"shares" => share_params}, socket) do
    list = socket.assigns.list

    user_ids =
      share_params
      |> Enum.filter(fn {_id, val} -> val == "true" end)
      |> Enum.map(fn {id, _val} -> id end)

    Shopping.share_list(list.id, user_ids)

    {:noreply,
     socket
     |> put_flash(:info, "Sharing updated")
     |> push_patch(to: ~p"/households/#{socket.assigns.household.id}/shopping/#{list.id}")}
  end

  def handle_event("save_shares", _params, socket) do
    list = socket.assigns.list
    Shopping.share_list(list.id, [])

    {:noreply,
     socket
     |> put_flash(:info, "Sharing updated")
     |> push_patch(to: ~p"/households/#{socket.assigns.household.id}/shopping/#{list.id}")}
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
        {@list.name}
        <:subtitle>
          {length(@unchecked)} items remaining
          <%= if length(@checked) > 0 do %>
            · {length(@checked)} checked
          <% end %>
        </:subtitle>
        <:actions>
          <%= if @is_owner and not @list.is_main and @list.created_by_id != nil do %>
            <.link
              patch={~p"/households/#{@household.id}/shopping/#{@list.id}/share"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-share" class="size-4 mr-1" /> Share
            </.link>
          <% end %>
          <%= if length(@checked) > 0 do %>
            <div class="dropdown dropdown-end">
              <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
                <.icon name="hero-ellipsis-vertical" class="size-5" />
              </div>
              <ul
                tabindex="0"
                class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52"
              >
                <%= unless @list.add_to_pantry do %>
                  <li>
                    <button phx-click="transfer_to_pantry">
                      <.icon name="hero-arrow-up-tray" class="size-4" /> Add to Pantry
                    </button>
                  </li>
                <% end %>
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

      <.modal
        :if={@live_action == :share}
        id="share-modal"
        show
        close_button={false}
        on_cancel={JS.patch(~p"/households/#{@household.id}/shopping/#{@list.id}")}
      >
        <.header>
          Share List
          <:subtitle>Choose household members to share this list with</:subtitle>
        </.header>

        <form phx-submit="save_shares" class="mt-4">
          <div class="space-y-3">
            <%= for member <- @members do %>
              <label class="flex items-center gap-3 p-3 rounded-lg hover:bg-base-200 cursor-pointer">
                <input
                  type="checkbox"
                  name={"shares[#{member.user.id}]"}
                  value="true"
                  checked={MapSet.member?(@shared_user_ids, member.user.id)}
                  class="checkbox checkbox-primary"
                />
                <div>
                  <div class="font-medium">{member.user.name || member.user.email}</div>
                  <div class="text-sm text-base-content/60">{member.role}</div>
                </div>
              </label>
            <% end %>
          </div>

          <%= if @members == [] do %>
            <p class="text-center text-base-content/60 py-4">
              No other household members to share with.
            </p>
          <% end %>

          <div class="mt-6 flex justify-end gap-2">
            <.link
              patch={~p"/households/#{@household.id}/shopping/#{@list.id}"}
              class="btn btn-ghost"
            >
              Cancel
            </.link>
            <button type="submit" class="btn btn-primary">Save</button>
          </div>
        </form>
      </.modal>

      <div class="mt-4 flex items-center gap-2">
        <label class="label cursor-pointer gap-2">
          <span class="label-text text-sm">Auto-add to pantry</span>
          <input
            type="checkbox"
            class="toggle toggle-primary toggle-sm"
            checked={@list.add_to_pantry}
            disabled={@list.is_main}
            phx-click="toggle_add_to_pantry"
          />
        </label>
        <%= if @list.is_main do %>
          <span class="text-xs text-base-content/50">(always on)</span>
        <% end %>
      </div>

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
                <span class="font-medium">{item.name}</span>
                <%= if item.quantity && Decimal.compare(item.quantity, Decimal.new(1)) != :eq do %>
                  <span class="text-base-content/70 text-sm ml-2">
                    ({Decimal.to_string(item.quantity)}{if item.unit, do: " #{item.unit}"})
                  </span>
                <% end %>
                <%= if item.category do %>
                  <span class="badge badge-sm badge-ghost ml-2">{item.category.name}</span>
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
            Checked ({length(@checked)})
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
                    <span class="line-through">{item.name}</span>
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
