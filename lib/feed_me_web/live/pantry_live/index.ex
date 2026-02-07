defmodule FeedMeWeb.PantryLive.Index do
  use FeedMeWeb, :live_view

  alias FeedMe.Pantry
  alias FeedMe.Pantry.Item

  @impl true
  def mount(_params, _session, socket) do
    household = socket.assigns.household

    if connected?(socket), do: Pantry.subscribe(household.id)

    locations = Pantry.list_storage_locations(household.id)

    {:ok,
     socket
     |> assign(:active_tab, :pantry)
     |> assign(:locations, locations)
     |> assign(:current_location, nil)
     |> assign(:categories, [])
     |> assign(:items, [])
     |> assign(:filter_category, nil)
     |> assign(:search_query, "")
     |> assign(:show_new_location, false)
     |> assign(:show_manage_locations, false)
     |> assign(:editing_location, nil)
     |> assign(:page_title, "On Hand")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    household = socket.assigns.household

    location =
      case params["location_id"] do
        nil ->
          # Default to Pantry location
          Pantry.get_pantry_location(household.id) ||
            Pantry.get_default_storage_location(household.id)

        location_id ->
          Pantry.get_storage_location(location_id, household.id)
      end

    if location do
      categories = Pantry.list_categories(location.id)
      items = Pantry.list_items(household.id, storage_location_id: location.id)

      {:noreply,
       socket
       |> assign(:current_location, location)
       |> assign(:categories, categories)
       |> assign(:items, items)
       |> assign(:filter_category, nil)
       |> assign(:search_query, "")
       |> assign(:page_title, location.name)}
    else
      # Location not found, redirect to base pantry
      {:noreply,
       socket
       |> put_flash(:error, "Location not found")
       |> push_navigate(to: ~p"/households/#{household.id}/pantry")}
    end
  end

  @impl true
  def handle_event("change_location", %{"location_id" => location_id}, socket) do
    household = socket.assigns.household

    {:noreply,
     push_patch(socket, to: ~p"/households/#{household.id}/pantry/locations/#{location_id}")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    item = Pantry.get_item(id, socket.assigns.household.id)

    if item do
      {:ok, _} = Pantry.delete_item(item)

      {:noreply,
       socket
       |> put_flash(:info, "Item deleted successfully")
       |> reload_items()}
    else
      {:noreply, put_flash(socket, :error, "Item not found")}
    end
  end

  def handle_event("filter", %{"category" => category_id}, socket) do
    filter = if category_id == "", do: nil, else: category_id

    items =
      if filter do
        Pantry.list_items(socket.assigns.household.id,
          storage_location_id: socket.assigns.current_location.id,
          category_id: filter
        )
      else
        Pantry.list_items(socket.assigns.household.id,
          storage_location_id: socket.assigns.current_location.id
        )
      end

    {:noreply,
     socket
     |> assign(:filter_category, filter)
     |> assign(:items, items)}
  end

  def handle_event("search", %{"query" => query}, socket) do
    items =
      if query == "" do
        Pantry.list_items(socket.assigns.household.id,
          storage_location_id: socket.assigns.current_location.id
        )
      else
        Pantry.search_items(socket.assigns.household.id, query,
          storage_location_id: socket.assigns.current_location.id
        )
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:items, items)}
  end

  def handle_event("toggle_stock", %{"id" => id}, socket) do
    item = Pantry.get_item(id, socket.assigns.household.id)

    if item do
      {:ok, _} = Pantry.update_item(item, %{always_in_stock: !item.always_in_stock})
      {:noreply, reload_items(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("quick_adjust", %{"id" => id, "change" => change}, socket) do
    item = Pantry.get_item(id, socket.assigns.household.id)
    user = socket.assigns.current_scope.user
    change_decimal = Decimal.new(change)

    if item do
      {:ok, _} = Pantry.adjust_quantity(item, change_decimal, user, reason: "Quick adjust")
      {:noreply, reload_items(socket)}
    else
      {:noreply, socket}
    end
  end

  # -- Location management events --

  def handle_event("show_new_location", _params, socket) do
    {:noreply, assign(socket, :show_new_location, true)}
  end

  def handle_event("cancel_new_location", _params, socket) do
    {:noreply, assign(socket, :show_new_location, false)}
  end

  def handle_event("create_location", %{"location" => params}, socket) do
    household = socket.assigns.household

    template_key =
      case params["template"] do
        "" -> Pantry.suggest_template(params["name"])
        key -> String.to_existing_atom(key)
      end

    attrs = %{
      name: params["name"],
      icon: params["icon"] || "hero-archive-box",
      household_id: household.id
    }

    opts = if template_key, do: [template: template_key], else: []

    case Pantry.create_storage_location(attrs, opts) do
      {:ok, location} ->
        locations = Pantry.list_storage_locations(household.id)

        {:noreply,
         socket
         |> assign(:locations, locations)
         |> assign(:show_new_location, false)
         |> put_flash(:info, "Location \"#{location.name}\" created")
         |> push_patch(to: ~p"/households/#{household.id}/pantry/locations/#{location.id}")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create: #{error_messages(changeset)}")}
    end
  end

  def handle_event("show_manage_locations", _params, socket) do
    {:noreply, assign(socket, :show_manage_locations, true)}
  end

  def handle_event("close_manage_locations", _params, socket) do
    {:noreply, assign(socket, :show_manage_locations, false)}
  end

  def handle_event("delete_location", %{"id" => id}, socket) do
    household = socket.assigns.household
    location = Pantry.get_storage_location(id, household.id)

    if location do
      case Pantry.delete_storage_location(location) do
        {:ok, _} ->
          locations = Pantry.list_storage_locations(household.id)

          {:noreply,
           socket
           |> assign(:locations, locations)
           |> put_flash(:info, "Location deleted. Items moved to On Hand.")
           |> push_patch(to: ~p"/households/#{household.id}/pantry")}

        {:error, :cannot_delete_default} ->
          {:noreply, put_flash(socket, :error, "Cannot delete the default location")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete location")}
      end
    else
      {:noreply, put_flash(socket, :error, "Location not found")}
    end
  end

  def handle_event("move_item", %{"id" => item_id, "location_id" => location_id}, socket) do
    item = Pantry.get_item(item_id, socket.assigns.household.id)

    if item do
      {:ok, _} = Pantry.move_item_to_location(item, location_id)

      {:noreply,
       socket
       |> put_flash(:info, "#{item.name} moved")
       |> reload_items()}
    else
      {:noreply, put_flash(socket, :error, "Item not found")}
    end
  end

  @impl true
  def handle_info({:item_created, _item}, socket), do: {:noreply, reload_items(socket)}
  def handle_info({:item_updated, _item}, socket), do: {:noreply, reload_items(socket)}
  def handle_info({:item_deleted, _item}, socket), do: {:noreply, reload_items(socket)}

  def handle_info({:restock_needed, item}, socket) do
    {:noreply, put_flash(socket, :info, "#{item.name} needs restocking!")}
  end

  def handle_info({:storage_location_created, _}, socket) do
    {:noreply,
     assign(socket, :locations, Pantry.list_storage_locations(socket.assigns.household.id))}
  end

  def handle_info({:storage_location_updated, _}, socket) do
    {:noreply,
     assign(socket, :locations, Pantry.list_storage_locations(socket.assigns.household.id))}
  end

  def handle_info({:storage_location_deleted, _}, socket) do
    {:noreply,
     assign(socket, :locations, Pantry.list_storage_locations(socket.assigns.household.id))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp reload_items(socket) do
    location = socket.assigns.current_location

    if location do
      items =
        Pantry.list_items(socket.assigns.household.id, storage_location_id: location.id)

      categories = Pantry.list_categories(location.id)
      assign(socket, items: items, categories: categories)
    else
      socket
    end
  end

  defp error_messages(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map(fn {k, v} -> "#{k} #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        On Hand
        <:subtitle>{@household.name}</:subtitle>
        <:actions>
          <%= if @current_location do %>
            <.link
              navigate={
                ~p"/households/#{@household.id}/pantry/locations/#{@current_location.id}/categories"
              }
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-tag" class="size-4" /> Categories
            </.link>
          <% end %>
        </:actions>
      </.header>

      <%!-- Location Selector --%>
      <div class="mt-4 flex flex-wrap items-center gap-2">
        <%= for location <- @locations do %>
          <button
            phx-click="change_location"
            phx-value-location_id={location.id}
            class={[
              "btn btn-sm",
              @current_location && @current_location.id == location.id && "btn-primary",
              !(@current_location && @current_location.id == location.id) && "btn-ghost"
            ]}
          >
            <%= if location.icon do %>
              <.icon name={location.icon} class="size-4" />
            <% end %>
            {location.name}
          </button>
        <% end %>
        <button
          phx-click="show_new_location"
          class="btn btn-sm btn-ghost btn-circle"
          title="Add Location"
        >
          <.icon name="hero-plus" class="size-4" />
        </button>
        <button
          phx-click="show_manage_locations"
          class="btn btn-sm btn-ghost btn-circle"
          title="Manage Locations"
        >
          <.icon name="hero-cog-6-tooth" class="size-4" />
        </button>
      </div>

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
                  {category.name}
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
            <p class="mt-2 text-base-content/70">
              <%= if @current_location do %>
                No items in {@current_location.name}.
              <% else %>
                Your inventory is empty.
              <% end %>
            </p>
            <p class="mt-2 text-base-content/50">
              Items are added automatically from your shopping lists.
            </p>
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for item <- @items do %>
              <div class="card bg-base-100 shadow-sm border border-base-200">
                <div class="card-body p-4 flex-row items-center justify-between">
                  <div class="flex-1">
                    <.link
                      navigate={
                        if @current_location do
                          ~p"/households/#{@household.id}/pantry/locations/#{@current_location.id}/#{item.id}"
                        else
                          ~p"/households/#{@household.id}/pantry/#{item.id}"
                        end
                      }
                      class="font-medium hover:text-primary"
                    >
                      {item.name}
                    </.link>
                    <div class="text-sm text-base-content/70 flex items-center gap-2 flex-wrap">
                      <%= if item.category do %>
                        <span class="badge badge-sm">{item.category.name}</span>
                      <% end %>
                      <%= if item.expiration_date do %>
                        <span class={[
                          Item.expired?(item) && "text-error",
                          Item.expiring_soon?(item, 7) && !Item.expired?(item) && "text-warning"
                        ]}>
                          Exp: {item.expiration_date}
                        </span>
                      <% end %>
                      <button
                        phx-click="toggle_stock"
                        phx-value-id={item.id}
                        class={[
                          "badge badge-xs cursor-pointer transition-colors",
                          item.always_in_stock && "badge-info",
                          not item.always_in_stock && "badge-ghost opacity-50 hover:opacity-100"
                        ]}
                        title={
                          if item.always_in_stock,
                            do: "Click to disable keep-in-stock",
                            else: "Click to keep in stock"
                        }
                      >
                        {if item.always_in_stock, do: "Keep in stock", else: "Keep in stock"}
                      </button>
                    </div>
                  </div>
                  <div class="flex items-center gap-2">
                    <%!-- Move to button for On Hand (default) location --%>
                    <%= if @current_location && @current_location.is_default do %>
                      <div class="dropdown dropdown-end">
                        <div
                          tabindex="0"
                          role="button"
                          class="btn btn-xs btn-ghost"
                          title="Move to..."
                        >
                          <.icon name="hero-arrow-right" class="size-3" />
                        </div>
                        <ul
                          tabindex="0"
                          class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-40"
                        >
                          <%= for loc <- @locations, loc.id != @current_location.id do %>
                            <li>
                              <button
                                phx-click="move_item"
                                phx-value-id={item.id}
                                phx-value-location_id={loc.id}
                              >
                                {loc.name}
                              </button>
                            </li>
                          <% end %>
                        </ul>
                      </div>
                    <% end %>
                    <button
                      phx-click="quick_adjust"
                      phx-value-id={item.id}
                      phx-value-change="-1"
                      class="btn btn-sm btn-circle btn-ghost"
                    >
                      <.icon name="hero-minus" class="size-4" />
                    </button>
                    <span class="font-mono min-w-[4rem] text-center">
                      {if item.quantity, do: Decimal.to_string(item.quantity), else: "—"}{if item.unit,
                        do: " #{item.unit}"}
                    </span>
                    <button
                      phx-click="quick_adjust"
                      phx-value-id={item.id}
                      phx-value-change="1"
                      class="btn btn-sm btn-circle btn-ghost"
                    >
                      <.icon name="hero-plus" class="size-4" />
                    </button>
                    <button
                      phx-click="delete"
                      phx-value-id={item.id}
                      data-confirm="Are you sure you want to delete this item?"
                      class="btn btn-sm btn-ghost text-error"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <.back navigate={~p"/households/#{@household.id}"}>Back to household</.back>

      <%!-- New Location Modal --%>
      <.modal
        :if={@show_new_location}
        id="new-location-modal"
        show
        on_cancel={JS.push("cancel_new_location")}
      >
        <.header>
          Add Storage Location
          <:subtitle>Create a new place to track items</:subtitle>
        </.header>

        <form phx-submit="create_location" class="mt-4 space-y-4">
          <div class="form-control">
            <label class="label"><span class="label-text">Name</span></label>
            <input
              type="text"
              name="location[name]"
              placeholder="e.g., Garage, Pet Closet, Bulk Storage..."
              class="input input-bordered"
              autofocus
              required
            />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Category Template</span></label>
            <select name="location[template]" class="select select-bordered">
              <option value="">None (empty)</option>
              <option value="pantry">Food Pantry</option>
              <option value="garage">Garage</option>
              <option value="bulk_storage">Bulk Storage</option>
              <option value="pet_supplies">Pet Supplies</option>
              <option value="garden_shed">Garden Shed</option>
            </select>
            <label class="label">
              <span class="label-text-alt">Pre-populate with common categories</span>
            </label>
          </div>
          <input type="hidden" name="location[icon]" value="hero-archive-box" />
          <div class="flex justify-end gap-2 mt-6">
            <button type="button" phx-click="cancel_new_location" class="btn btn-ghost">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary">Create</button>
          </div>
        </form>
      </.modal>

      <%!-- Manage Locations Modal --%>
      <.modal
        :if={@show_manage_locations}
        id="manage-locations-modal"
        show
        on_cancel={JS.push("close_manage_locations")}
      >
        <.header>
          Manage Locations
          <:subtitle>Edit or delete storage locations</:subtitle>
        </.header>

        <div class="mt-4 space-y-2">
          <%= for location <- @locations do %>
            <div class="flex items-center justify-between p-3 rounded-lg bg-base-200">
              <div class="flex items-center gap-2">
                <%= if location.icon do %>
                  <.icon name={location.icon} class="size-5 text-base-content/70" />
                <% end %>
                <span class="font-medium">{location.name}</span>
                <%= if location.is_default do %>
                  <span class="badge badge-xs badge-info">Default</span>
                <% end %>
              </div>
              <%= unless location.is_default do %>
                <button
                  phx-click="delete_location"
                  phx-value-id={location.id}
                  data-confirm={"Delete \"#{location.name}\"? Items will be moved to On Hand."}
                  class="btn btn-ghost btn-sm text-error"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="mt-4 flex justify-end">
          <button phx-click="close_manage_locations" class="btn btn-ghost">Close</button>
        </div>
      </.modal>
    </div>
    """
  end
end
