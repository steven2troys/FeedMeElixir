defmodule FeedMeWeb.PantryLive.Show do
  use FeedMeWeb, :live_view

  import FeedMeWeb.NutritionComponent

  alias FeedMe.Pantry
  alias FeedMe.Pantry.Item

  @impl true
  def mount(params, _session, socket) do
    household = socket.assigns.household
    item_id = params["id"]
    location_id = params["location_id"]

    item = Pantry.get_item(item_id, household.id)

    if item do
      transactions = Pantry.list_transactions_for_item(item.id, limit: 20)
      locations = Pantry.list_storage_locations(household.id)
      location = if location_id, do: Pantry.get_storage_location(location_id, household.id)

      {:ok,
       socket
       |> assign(:active_tab, :pantry)
       |> assign(:item, item)
       |> assign(:transactions, transactions)
       |> assign(:locations, locations)
       |> assign(:current_location, location)
       |> assign(:page_title, item.name)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Item not found")
       |> push_navigate(to: ~p"/households/#{household.id}/pantry")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    item = Pantry.get_item(id, socket.assigns.household.id)

    if item do
      {:ok, _} = Pantry.delete_item(item)

      {:noreply,
       socket
       |> put_flash(:info, "#{item.name} removed from inventory")
       |> push_navigate(to: back_path(socket.assigns))}
    else
      {:noreply, put_flash(socket, :error, "Item not found")}
    end
  end

  def handle_event("adjust", %{"amount" => amount}, socket) do
    user = socket.assigns.current_scope.user
    item = socket.assigns.item

    {:ok, updated_item} =
      Pantry.adjust_quantity(item, Decimal.new(amount), user, reason: "Manual adjustment")

    {:noreply,
     socket
     |> assign(:item, Pantry.get_item(updated_item.id))
     |> assign(:transactions, Pantry.list_transactions_for_item(item.id, limit: 20))}
  end

  def handle_event("move_item", %{"location_id" => location_id}, socket) do
    item = socket.assigns.item

    {:ok, updated} = Pantry.move_item_to_location(item, location_id)
    location = Pantry.get_storage_location(location_id)

    {:noreply,
     socket
     |> assign(:item, Pantry.get_item(updated.id))
     |> put_flash(:info, "Moved to #{location.name}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        {@item.name}
        <:subtitle>
          {if @item.category, do: @item.category.name, else: "Uncategorized"}
        </:subtitle>
        <:actions>
          <%!-- Move to dropdown --%>
          <div class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-right" class="size-4" /> Move to
            </div>
            <ul
              tabindex="0"
              class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-48"
            >
              <%= for loc <- @locations, loc.id != @item.storage_location_id do %>
                <li>
                  <button phx-click="move_item" phx-value-location_id={loc.id}>
                    <%= if loc.icon do %>
                      <.icon name={loc.icon} class="size-4" />
                    <% end %>
                    {loc.name}
                  </button>
                </li>
              <% end %>
            </ul>
          </div>
          <button
            phx-click="delete"
            phx-value-id={@item.id}
            data-confirm="Are you sure you want to delete this item?"
            class="btn btn-ghost btn-sm text-error"
          >
            <.icon name="hero-trash" class="size-4" /> Remove
          </button>
        </:actions>
      </.header>

      <div class="mt-8 grid gap-6 sm:grid-cols-2">
        <div class="card bg-base-100 shadow border border-base-200">
          <div class="card-body">
            <h3 class="card-title text-sm">Current Quantity</h3>
            <p class="text-3xl font-bold">
              {Decimal.to_string(@item.quantity)}
              <span class="text-lg font-normal text-base-content/70">{@item.unit}</span>
            </p>
            <div class="card-actions mt-4">
              <form phx-submit="adjust" class="flex gap-2 w-full">
                <input
                  type="number"
                  name="amount"
                  placeholder="Amount"
                  class="input input-bordered flex-1"
                  step="any"
                />
                <button type="submit" class="btn btn-primary">Adjust</button>
              </form>
            </div>
          </div>
        </div>

        <div class="card bg-base-100 shadow border border-base-200">
          <div class="card-body">
            <h3 class="card-title text-sm">Status</h3>
            <div class="space-y-2">
              <%= if @item.expiration_date do %>
                <div class={[
                  "flex items-center gap-2",
                  Item.expired?(@item) && "text-error",
                  Item.expiring_soon?(@item, 7) && !Item.expired?(@item) && "text-warning"
                ]}>
                  <.icon name="hero-calendar" class="size-5" />
                  <span>
                    <%= if Item.expired?(@item) do %>
                      Expired {@item.expiration_date}
                    <% else %>
                      Expires {@item.expiration_date}
                    <% end %>
                  </span>
                </div>
              <% end %>

              <%= if @item.always_in_stock do %>
                <div class="flex items-center gap-2 text-info">
                  <.icon name="hero-arrow-path" class="size-5" />
                  <span>
                    Auto-restock when &le; {Decimal.to_string(
                      @item.restock_threshold || Decimal.new(0)
                    )}
                  </span>
                </div>
                <%= if Item.needs_restock?(@item) do %>
                  <div class="alert alert-warning">
                    <.icon name="hero-exclamation-triangle" class="size-5" />
                    <span>Needs restocking!</span>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <%= if @item.notes do %>
        <div class="mt-6 card bg-base-100 shadow border border-base-200">
          <div class="card-body">
            <h3 class="card-title text-sm">Notes</h3>
            <p class="whitespace-pre-wrap">{@item.notes}</p>
          </div>
        </div>
      <% end %>

      <div class="mt-6">
        <.nutrition_card nutrition={@item.nutrition} display={@nutrition_display} title="Nutrition" />
      </div>

      <div class="mt-6">
        <h3 class="font-semibold mb-4">Recent Activity</h3>
        <%= if @transactions == [] do %>
          <p class="text-base-content/70">No activity yet.</p>
        <% else %>
          <div class="space-y-2">
            <%= for tx <- @transactions do %>
              <div class="flex items-center justify-between py-2 border-b border-base-200">
                <div>
                  <span class={[
                    "badge badge-sm",
                    tx.action == :add && "badge-success",
                    tx.action == :remove && "badge-error",
                    tx.action == :use && "badge-warning",
                    tx.action == :adjust && "badge-info"
                  ]}>
                    {tx.action}
                  </span>
                  <span class="ml-2 font-mono">
                    {if Decimal.compare(tx.quantity_change, Decimal.new(0)) == :gt, do: "+", else: ""}{Decimal.to_string(
                      tx.quantity_change
                    )}
                  </span>
                  <%= if tx.reason do %>
                    <span class="text-base-content/70 text-sm ml-2">({tx.reason})</span>
                  <% end %>
                </div>
                <div class="text-sm text-base-content/70">
                  {Calendar.strftime(tx.inserted_at, "%b %d, %H:%M")}
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <.back navigate={back_path(assigns)}>Back to inventory</.back>
    </div>
    """
  end

  defp back_path(assigns) do
    case assigns.current_location do
      nil -> ~p"/households/#{assigns.household.id}/pantry"
      loc -> ~p"/households/#{assigns.household.id}/pantry/locations/#{loc.id}"
    end
  end
end
