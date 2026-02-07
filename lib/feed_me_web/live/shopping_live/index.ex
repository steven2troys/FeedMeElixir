defmodule FeedMeWeb.ShoppingLive.Index do
  use FeedMeWeb, :live_view

  alias FeedMe.Shopping
  alias FeedMe.Shopping.List, as: ShoppingList

  @impl true
  def mount(_params, _session, socket) do
    # household and role are set by HouseholdHooks
    household = socket.assigns.household
    user = socket.assigns.current_scope.user

    if connected?(socket), do: Shopping.subscribe(household.id)

    lists = Shopping.list_shopping_lists(household.id, user.id)

    {:ok,
     socket
     |> assign(:active_tab, :shopping)
     |> assign(:lists, lists)
     |> assign(:page_title, "Shopping Lists")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Shopping Lists")
    |> assign(:list, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Shopping List")
    |> assign(:list, %ShoppingList{household_id: socket.assigns.household.id})
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    list = Shopping.get_list(id, socket.assigns.household.id)

    cond do
      is_nil(list) || list.is_main ->
        {:noreply, put_flash(socket, :error, "Cannot delete the main shopping list")}

      list.created_by_id != nil && list.created_by_id != user.id ->
        {:noreply, put_flash(socket, :error, "Only the list owner can delete this list")}

      true ->
        {:ok, _} = Shopping.delete_list(list)
        {:noreply, socket |> put_flash(:info, "List deleted") |> reload_lists()}
    end
  end

  def handle_event("leave_list", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    Shopping.unshare_list(id, user.id)

    {:noreply,
     socket
     |> put_flash(:info, "Left list")
     |> reload_lists()}
  end

  def handle_event("create_main", _params, socket) do
    Shopping.get_or_create_main_list(socket.assigns.household.id)

    {:noreply,
     socket
     |> put_flash(:info, "Main shopping list created")
     |> reload_lists()}
  end

  def handle_event("add_restock_items", _params, socket) do
    user = socket.assigns.current_scope.user
    Shopping.add_restock_items_to_main_list(socket.assigns.household.id, user)

    {:noreply,
     socket
     |> put_flash(:info, "Items needing restock added to shopping list")
     |> reload_lists()}
  end

  @impl true
  def handle_info({:list_created, _list}, socket), do: {:noreply, reload_lists(socket)}
  def handle_info({:list_updated, _list}, socket), do: {:noreply, reload_lists(socket)}
  def handle_info({:list_deleted, _list}, socket), do: {:noreply, reload_lists(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload_lists(socket) do
    user = socket.assigns.current_scope.user
    assign(socket, :lists, Shopping.list_shopping_lists(socket.assigns.household.id, user.id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        Shopping Lists
        <:subtitle>{@household.name}</:subtitle>
        <:actions>
          <button phx-click="add_restock_items" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-path" class="size-4" /> Add Restock Items
          </button>
          <.link patch={~p"/households/#{@household.id}/shopping/new"}>
            <.button>New List</.button>
          </.link>
        </:actions>
      </.header>

      <div class="mt-6">
        <%= if @lists == [] do %>
          <div class="text-center py-12 bg-base-200 rounded-lg">
            <.icon name="hero-shopping-cart" class="size-12 mx-auto text-base-content/50" />
            <p class="mt-2 text-base-content/70">No shopping lists yet.</p>
            <button phx-click="create_main" class="btn btn-primary mt-4">
              Create Shopping List
            </button>
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for list <- @lists do %>
              <% is_owner =
                is_nil(list.created_by_id) or list.created_by_id == @current_scope.user.id %>
              <% is_shared_with_me = not is_owner and not list.is_main %>
              <% has_shares = is_owner and list.shares != [] %>
              <.link
                navigate={~p"/households/#{@household.id}/shopping/#{list.id}"}
                class="card bg-base-100 shadow-sm border border-base-200 hover:border-primary transition-colors"
              >
                <div class="card-body p-4 flex-row items-center justify-between">
                  <div class="flex items-center gap-3">
                    <%= if list.is_main do %>
                      <span class="badge badge-primary">Main</span>
                    <% end %>
                    <span class="font-medium">{list.name}</span>
                    <%= if is_shared_with_me do %>
                      <span class="badge badge-sm badge-outline badge-info">Shared with you</span>
                    <% end %>
                    <%= if has_shares do %>
                      <span class="badge badge-sm badge-outline badge-secondary">
                        <.icon name="hero-share" class="size-3 mr-1" />Shared
                      </span>
                    <% end %>
                    <%= if list.auto_add_to_location do %>
                      <span class="badge badge-sm badge-accent">
                        &rarr; {list.auto_add_to_location.name}
                      </span>
                    <% end %>
                    <span class={[
                      "badge badge-sm",
                      list.status == :active && "badge-success",
                      list.status == :completed && "badge-info",
                      list.status == :archived && "badge-ghost"
                    ]}>
                      {list.status}
                    </span>
                  </div>
                  <%= if is_owner and not list.is_main do %>
                    <button
                      phx-click="delete"
                      phx-value-id={list.id}
                      data-confirm="Are you sure you want to delete this list?"
                      class="btn btn-ghost btn-sm text-error"
                      onclick="event.preventDefault(); event.stopPropagation();"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  <% end %>
                  <%= if is_shared_with_me do %>
                    <button
                      phx-click="leave_list"
                      phx-value-id={list.id}
                      data-confirm="Leave this list? You'll need to be re-shared to see it again."
                      class="btn btn-ghost btn-sm"
                      onclick="event.preventDefault(); event.stopPropagation();"
                      title="Leave"
                    >
                      <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
                    </button>
                  <% end %>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>

      <.back navigate={~p"/households/#{@household.id}"}>Back to household</.back>

      <.modal
        :if={@live_action == :new}
        id="list-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@household.id}/shopping")}
      >
        <.live_component
          module={FeedMeWeb.ShoppingLive.ListFormComponent}
          id={:new}
          title="New Shopping List"
          action={@live_action}
          list={@list}
          household={@household}
          current_scope={@current_scope}
          patch={~p"/households/#{@household.id}/shopping"}
        />
      </.modal>
    </div>
    """
  end
end
