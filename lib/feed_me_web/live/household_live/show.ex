defmodule FeedMeWeb.HouseholdLive.Show do
  use FeedMeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # household and role are set by HouseholdHooks
    {:ok,
     socket
     |> assign(:active_tab, :dashboard)
     |> assign(:page_title, socket.assigns.household.name)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        Dashboard
        <:subtitle>
          <span class={[
            "badge",
            @role == :admin && "badge-primary",
            @role == :member && "badge-neutral"
          ]}>
            You are an <%= @role %>
          </span>
        </:subtitle>
      </.header>

      <div class="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <.dashboard_card
          title="Pantry"
          description="Manage your household inventory"
          href={~p"/households/#{@household.id}/pantry"}
          icon="hero-archive-box"
        />
        <.dashboard_card
          title="Members & Profiles"
          description="View members and taste profiles"
          href={~p"/households/#{@household.id}/members"}
          icon="hero-user-group"
        />
        <.dashboard_card
          title="Shopping Lists"
          description="Create and manage shopping lists"
          href={~p"/households/#{@household.id}/shopping"}
          icon="hero-shopping-cart"
        />
        <.dashboard_card
          title="Recipes"
          description="Browse and manage recipes"
          href={~p"/households/#{@household.id}/recipes"}
          icon="hero-book-open"
        />
        <.dashboard_card
          title="AI Chat"
          description="Get help from your AI assistant"
          href={~p"/households/#{@household.id}/chat"}
          icon="hero-chat-bubble-left-right"
        />
        <.dashboard_card
          title="Budget"
          description="Track your spending"
          href={~p"/households/#{@household.id}"}
          icon="hero-currency-dollar"
          disabled
        />
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :disabled, :boolean, default: false

  defp dashboard_card(assigns) do
    ~H"""
    <%= if @disabled do %>
      <div class="card bg-base-200 opacity-50 cursor-not-allowed">
        <div class="card-body p-5">
          <div class="flex items-center gap-4">
            <div class="p-3 rounded-xl bg-base-300">
              <.icon name={@icon} class="h-7 w-7 text-base-content/50" />
            </div>
            <div>
              <h3 class="card-title text-base text-base-content/70"><%= @title %></h3>
              <p class="text-sm text-base-content/50"><%= @description %></p>
            </div>
          </div>
          <p class="mt-2 text-xs text-base-content/40">Coming soon</p>
        </div>
      </div>
    <% else %>
      <.link navigate={@href} class="block group">
        <div class="card bg-base-100 border border-base-300 hover:border-primary hover:shadow-lg transition-all duration-200">
          <div class="card-body p-5">
            <div class="flex items-center gap-4">
              <div class="p-3 rounded-xl bg-primary/10 group-hover:bg-primary/20 transition-colors">
                <.icon name={@icon} class="h-7 w-7 text-primary" />
              </div>
              <div>
                <h3 class="card-title text-base text-base-content"><%= @title %></h3>
                <p class="text-sm text-base-content/60"><%= @description %></p>
              </div>
            </div>
          </div>
        </div>
      </.link>
    <% end %>
    """
  end
end
