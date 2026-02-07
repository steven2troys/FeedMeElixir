defmodule FeedMeWeb.HouseholdLive.Show do
  use FeedMeWeb, :live_view

  alias FeedMe.Pantry
  alias FeedMe.Shopping
  alias FeedMe.Recipes

  @impl true
  def mount(_params, _session, socket) do
    household = socket.assigns.household

    if connected?(socket) do
      Pantry.subscribe(household.id)
      Shopping.subscribe(household.id)
    end

    {:ok,
     socket
     |> assign(:active_tab, :dashboard)
     |> assign(:page_title, household.name)
     |> load_dashboard_data()}
  end

  defp load_dashboard_data(socket) do
    household_id = socket.assigns.household.id

    expired = Pantry.expired_items(household_id)
    expiring = Pantry.items_expiring_soon(household_id, 7)
    restock = Pantry.items_needing_restock(household_id)
    user_id = socket.assigns.current_scope.user.id
    shopping_lists = Shopping.list_shopping_lists(household_id, user_id)
    recent_recipes = Recipes.list_recipes(household_id, order_by: :newest) |> Enum.take(4)
    favorite_recipes = Recipes.list_recipes(household_id, favorites_only: true) |> Enum.take(4)

    socket
    |> assign(:expired_items, expired)
    |> assign(:expiring_items, expiring)
    |> assign(:restock_items, restock)
    |> assign(:shopping_lists, shopping_lists)
    |> assign(:recent_recipes, recent_recipes)
    |> assign(:favorite_recipes, favorite_recipes)
  end

  @impl true
  def handle_info({:pantry_updated, _}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  def handle_info({:shopping_updated, _}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  # Catch-all for other PubSub messages
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{@household.name}</h1>
          <p class="text-sm text-base-content/60">
            <span class={[
              "badge badge-sm",
              @role == :admin && "badge-primary",
              @role == :member && "badge-neutral"
            ]}>
              {@role}
            </span>
          </p>
        </div>
      </div>
      
    <!-- Alerts Section -->
      <%= if @expired_items != [] or @expiring_items != [] or @restock_items != [] do %>
        <div class="flex flex-wrap gap-2">
          <%= if @expired_items != [] do %>
            <.link
              navigate={~p"/households/#{@household.id}/pantry"}
              class="badge badge-error gap-1 py-3"
            >
              <.icon name="hero-exclamation-triangle" class="size-3.5" />
              {length(@expired_items)} expired
            </.link>
          <% end %>
          <%= if @expiring_items != [] do %>
            <.link
              navigate={~p"/households/#{@household.id}/pantry"}
              class="badge badge-warning gap-1 py-3"
            >
              <.icon name="hero-clock" class="size-3.5" />
              {length(@expiring_items)} expiring soon
            </.link>
          <% end %>
          <%= if @restock_items != [] do %>
            <.link
              navigate={~p"/households/#{@household.id}/pantry"}
              class="badge badge-info gap-1 py-3"
            >
              <.icon name="hero-arrow-path" class="size-3.5" />
              {length(@restock_items)} need restock
            </.link>
          <% end %>
        </div>
      <% end %>
      
    <!-- Dashboard Grid -->
      <div class="grid gap-4 sm:grid-cols-2">
        <!-- Expiring Soon -->
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body p-4">
            <div class="flex items-center justify-between mb-3">
              <h3 class="font-semibold flex items-center gap-2">
                <.icon name="hero-clock" class="size-4 text-warning" /> Expiring Soon
              </h3>
              <.link
                navigate={~p"/households/#{@household.id}/pantry"}
                class="text-xs text-primary hover:underline"
              >
                View all
              </.link>
            </div>
            <%= if @expiring_items == [] do %>
              <p class="text-sm text-base-content/50">Nothing expiring this week.</p>
            <% else %>
              <ul class="space-y-1.5">
                <%= for item <- Enum.take(@expiring_items, 5) do %>
                  <li class="flex items-center justify-between text-sm">
                    <span class="truncate">{item.name}</span>
                    <span class="text-xs text-warning whitespace-nowrap ml-2">
                      {format_expiry(item.expiration_date)}
                    </span>
                  </li>
                <% end %>
              </ul>
              <%= if length(@expiring_items) > 5 do %>
                <p class="text-xs text-base-content/50 mt-2">
                  +{length(@expiring_items) - 5} more
                </p>
              <% end %>
            <% end %>
          </div>
        </div>
        
    <!-- Needs Restock -->
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body p-4">
            <div class="flex items-center justify-between mb-3">
              <h3 class="font-semibold flex items-center gap-2">
                <.icon name="hero-arrow-path" class="size-4 text-info" /> Needs Restock
              </h3>
              <.link
                navigate={~p"/households/#{@household.id}/pantry"}
                class="text-xs text-primary hover:underline"
              >
                View all
              </.link>
            </div>
            <%= if @restock_items == [] do %>
              <p class="text-sm text-base-content/50">Everything is well-stocked.</p>
            <% else %>
              <ul class="space-y-1.5">
                <%= for item <- Enum.take(@restock_items, 5) do %>
                  <li class="flex items-center justify-between text-sm">
                    <span class="truncate">{item.name}</span>
                    <span class="text-xs text-base-content/50 whitespace-nowrap ml-2">
                      {Decimal.to_string(item.quantity)} {item.unit}
                    </span>
                  </li>
                <% end %>
              </ul>
              <%= if length(@restock_items) > 5 do %>
                <p class="text-xs text-base-content/50 mt-2">
                  +{length(@restock_items) - 5} more
                </p>
              <% end %>
            <% end %>
          </div>
        </div>
        
    <!-- Shopping Lists -->
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body p-4">
            <div class="flex items-center justify-between mb-3">
              <h3 class="font-semibold flex items-center gap-2">
                <.icon name="hero-shopping-cart" class="size-4 text-secondary" /> Shopping Lists
              </h3>
              <.link
                navigate={~p"/households/#{@household.id}/shopping"}
                class="text-xs text-primary hover:underline"
              >
                View all
              </.link>
            </div>
            <%= if @shopping_lists == [] do %>
              <p class="text-sm text-base-content/50">No shopping lists yet.</p>
            <% else %>
              <ul class="space-y-1.5">
                <%= for list <- Enum.take(@shopping_lists, 4) do %>
                  <li>
                    <.link
                      navigate={~p"/households/#{@household.id}/shopping/#{list.id}"}
                      class="flex items-center justify-between text-sm hover:text-primary transition-colors"
                    >
                      <span class="truncate flex items-center gap-1.5">
                        <%= if list.is_main do %>
                          <span class="badge badge-xs badge-primary">Main</span>
                        <% end %>
                        {list.name}
                      </span>
                    </.link>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>
        
    <!-- Recent Recipes -->
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body p-4">
            <div class="flex items-center justify-between mb-3">
              <h3 class="font-semibold flex items-center gap-2">
                <.icon name="hero-book-open" class="size-4 text-accent" /> Recent Recipes
              </h3>
              <.link
                navigate={~p"/households/#{@household.id}/recipes"}
                class="text-xs text-primary hover:underline"
              >
                View all
              </.link>
            </div>
            <%= if @recent_recipes == [] do %>
              <p class="text-sm text-base-content/50">No recipes yet.</p>
            <% else %>
              <ul class="space-y-1.5">
                <%= for recipe <- @recent_recipes do %>
                  <li>
                    <.link
                      navigate={~p"/households/#{@household.id}/recipes/#{recipe.id}"}
                      class="flex items-center justify-between text-sm hover:text-primary transition-colors"
                    >
                      <span class="truncate">{recipe.title}</span>
                      <%= if recipe.is_favorite do %>
                        <.icon name="hero-heart-solid" class="size-3.5 text-error shrink-0" />
                      <% end %>
                    </.link>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Quick Actions -->
      <div class="flex flex-wrap gap-2">
        <.link
          navigate={~p"/households/#{@household.id}/pantry"}
          class="btn btn-sm btn-outline gap-1"
        >
          <.icon name="hero-plus" class="size-3.5" /> Add to Pantry
        </.link>
        <.link
          navigate={~p"/households/#{@household.id}/shopping"}
          class="btn btn-sm btn-outline gap-1"
        >
          <.icon name="hero-plus" class="size-3.5" /> New Shopping List
        </.link>
        <.link
          navigate={~p"/households/#{@household.id}/recipes"}
          class="btn btn-sm btn-outline gap-1"
        >
          <.icon name="hero-plus" class="size-3.5" /> Add Recipe
        </.link>
      </div>
    </div>
    """
  end

  defp format_expiry(nil), do: ""

  defp format_expiry(date) do
    days = Date.diff(date, Date.utc_today())

    cond do
      days < 0 -> "#{abs(days)}d ago"
      days == 0 -> "Today"
      days == 1 -> "Tomorrow"
      true -> "#{days}d left"
    end
  end
end
