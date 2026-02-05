defmodule FeedMeWeb.PantryLive.Index do
  use FeedMeWeb, :live_view

  alias FeedMe.Pantry
  alias FeedMe.Pantry.Item

  @impl true
  def mount(_params, _session, socket) do
    # household and role are set by HouseholdHooks
    household = socket.assigns.household

    if connected?(socket), do: Pantry.subscribe(household.id)

    categories = Pantry.list_categories(household.id)
    items = Pantry.list_items(household.id)

    {:ok,
     socket
     |> assign(:active_tab, :pantry)
     |> assign(:categories, categories)
     |> assign(:items, items)
     |> assign(:filter_category, nil)
     |> assign(:search_query, "")
     |> assign(:page_title, "Pantry")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Pantry")
    |> assign(:item, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Item")
    |> assign(:item, %Item{household_id: socket.assigns.household.id})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    item = Pantry.get_item(id, socket.assigns.household.id)

    socket
    |> assign(:page_title, "Edit Item")
    |> assign(:item, item)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    item = Pantry.get_item(id, socket.assigns.household.id)

    if item do
      {:ok, _} = Pantry.delete_item(item)

      {:noreply,
       socket
       |> put_flash(:info, "Item deleted successfully")
       |> assign(:items, Pantry.list_items(socket.assigns.household.id))}
    else
      {:noreply, put_flash(socket, :error, "Item not found")}
    end
  end

  def handle_event("filter", %{"category" => category_id}, socket) do
    filter = if category_id == "", do: nil, else: category_id

    items =
      if filter do
        Pantry.list_items(socket.assigns.household.id, category_id: filter)
      else
        Pantry.list_items(socket.assigns.household.id)
      end

    {:noreply,
     socket
     |> assign(:filter_category, filter)
     |> assign(:items, items)}
  end

  def handle_event("search", %{"query" => query}, socket) do
    items =
      if query == "" do
        Pantry.list_items(socket.assigns.household.id)
      else
        Pantry.search_items(socket.assigns.household.id, query)
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:items, items)}
  end

  def handle_event("quick_adjust", %{"id" => id, "change" => change}, socket) do
    item = Pantry.get_item(id, socket.assigns.household.id)
    user = socket.assigns.current_scope.user
    change_decimal = Decimal.new(change)

    if item do
      {:ok, _} = Pantry.adjust_quantity(item, change_decimal, user, reason: "Quick adjust")

      {:noreply,
       socket
       |> assign(:items, Pantry.list_items(socket.assigns.household.id))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:item_created, _item}, socket) do
    {:noreply, assign(socket, :items, Pantry.list_items(socket.assigns.household.id))}
  end

  def handle_info({:item_updated, _item}, socket) do
    {:noreply, assign(socket, :items, Pantry.list_items(socket.assigns.household.id))}
  end

  def handle_info({:item_deleted, _item}, socket) do
    {:noreply, assign(socket, :items, Pantry.list_items(socket.assigns.household.id))}
  end

  def handle_info({:restock_needed, item}, socket) do
    {:noreply, put_flash(socket, :info, "#{item.name} needs restocking!")}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        Pantry
        <:subtitle><%= @household.name %></:subtitle>
        <:actions>
          <.link navigate={~p"/households/#{@household.id}/pantry/categories"} class="btn btn-ghost btn-sm">
            <.icon name="hero-tag" class="size-4" /> Categories
          </.link>
          <.link patch={~p"/households/#{@household.id}/pantry/new"}>
            <.button>Add Item</.button>
          </.link>
        </:actions>
      </.header>

      <div class="mt-6 flex flex-col sm:flex-row gap-4">
        <div class="flex-1">
          <form phx-change="search" phx-submit="search">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search items..."
              class="input input-bordered w-full"
              phx-debounce="300"
            />
          </form>
        </div>
        <div>
          <form phx-change="filter">
            <select name="category" class="select select-bordered">
              <option value="">All Categories</option>
              <%= for category <- @categories do %>
                <option value={category.id} selected={@filter_category == category.id}>
                  <%= category.name %>
                </option>
              <% end %>
            </select>
          </form>
        </div>
      </div>

      <div class="mt-6">
        <%= if @items == [] do %>
          <div class="text-center py-12 bg-base-200 rounded-lg">
            <.icon name="hero-archive-box" class="size-12 mx-auto text-base-content/50" />
            <p class="mt-2 text-base-content/70">Your pantry is empty.</p>
            <.link patch={~p"/households/#{@household.id}/pantry/new"} class="btn btn-primary mt-4">
              Add your first item
            </.link>
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for item <- @items do %>
              <div class="card bg-base-100 shadow-sm border border-base-200">
                <div class="card-body p-4 flex-row items-center justify-between">
                  <div class="flex-1">
                    <.link navigate={~p"/households/#{@household.id}/pantry/#{item.id}"} class="font-medium hover:text-primary">
                      <%= item.name %>
                    </.link>
                    <div class="text-sm text-base-content/70 flex items-center gap-2">
                      <%= if item.category do %>
                        <span class="badge badge-sm"><%= item.category.name %></span>
                      <% end %>
                      <%= if item.expiration_date do %>
                        <span class={[
                          Item.expired?(item) && "text-error",
                          Item.expiring_soon?(item, 7) && !Item.expired?(item) && "text-warning"
                        ]}>
                          Exp: <%= item.expiration_date %>
                        </span>
                      <% end %>
                      <%= if item.always_in_stock do %>
                        <span class="badge badge-xs badge-info">Auto-restock</span>
                      <% end %>
                    </div>
                  </div>
                  <div class="flex items-center gap-2">
                    <button
                      phx-click="quick_adjust"
                      phx-value-id={item.id}
                      phx-value-change="-1"
                      class="btn btn-sm btn-circle btn-ghost"
                    >
                      <.icon name="hero-minus" class="size-4" />
                    </button>
                    <span class="font-mono min-w-[4rem] text-center">
                      <%= Decimal.to_string(item.quantity) %><%= if item.unit, do: " #{item.unit}" %>
                    </span>
                    <button
                      phx-click="quick_adjust"
                      phx-value-id={item.id}
                      phx-value-change="1"
                      class="btn btn-sm btn-circle btn-ghost"
                    >
                      <.icon name="hero-plus" class="size-4" />
                    </button>
                    <div class="dropdown dropdown-end">
                      <div tabindex="0" role="button" class="btn btn-sm btn-ghost">
                        <.icon name="hero-ellipsis-vertical" class="size-4" />
                      </div>
                      <ul tabindex="0" class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-32">
                        <li>
                          <.link patch={~p"/households/#{@household.id}/pantry/#{item.id}/edit"}>
                            Edit
                          </.link>
                        </li>
                        <li>
                          <button
                            phx-click="delete"
                            phx-value-id={item.id}
                            data-confirm="Are you sure you want to delete this item?"
                            class="text-error"
                          >
                            Delete
                          </button>
                        </li>
                      </ul>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <.back navigate={~p"/households/#{@household.id}"}>Back to household</.back>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="item-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@household.id}/pantry")}
      >
        <.live_component
          module={FeedMeWeb.PantryLive.ItemFormComponent}
          id={@item.id || :new}
          title={@page_title}
          action={@live_action}
          item={@item}
          categories={@categories}
          household={@household}
          patch={~p"/households/#{@household.id}/pantry"}
        />
      </.modal>
    </div>
    """
  end
end
