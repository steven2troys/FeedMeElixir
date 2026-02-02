defmodule FeedMeWeb.HouseholdLive.Index do
  use FeedMeWeb, :live_view

  alias FeedMe.Households
  alias FeedMe.Households.Household

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    households = Households.list_households_for_user(user)

    {:ok,
     socket
     |> assign(:households, households)
     |> assign(:page_title, "My Households")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Household")
    |> assign(:household, %Household{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "My Households")
    |> assign(:household, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    if Households.admin?(user, id) do
      household = Households.get_household(id)
      {:ok, _} = Households.delete_household(household)

      {:noreply,
       socket
       |> put_flash(:info, "Household deleted successfully")
       |> assign(:households, Households.list_households_for_user(user))}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to delete this household")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        My Households
        <:actions>
          <.link patch={~p"/households/new"}>
            <.button>New Household</.button>
          </.link>
        </:actions>
      </.header>

      <div class="mt-8 space-y-4">
        <%= if @households == [] do %>
          <div class="text-center py-12 bg-base-200 rounded-xl">
            <p class="text-base-content/60">You don't belong to any households yet.</p>
            <.link patch={~p"/households/new"} class="link link-primary mt-2 inline-block">
              Create your first household
            </.link>
          </div>
        <% else %>
          <div class="grid gap-4 sm:grid-cols-2">
            <%= for %{household: household, role: role} <- @households do %>
              <.link
                navigate={~p"/households/#{household.id}"}
                class="card bg-base-100 border border-base-300 hover:border-primary hover:shadow-lg transition-all duration-200"
              >
                <div class="card-body p-5">
                  <div class="flex items-center justify-between">
                    <h3 class="card-title text-base-content"><%= household.name %></h3>
                    <span class={[
                      "badge",
                      role == :admin && "badge-primary",
                      role == :member && "badge-neutral"
                    ]}>
                      <%= role %>
                    </span>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>

      <.modal
        :if={@live_action == :new}
        id="household-modal"
        show
        on_cancel={JS.patch(~p"/households")}
      >
        <.live_component
          module={FeedMeWeb.HouseholdLive.FormComponent}
          id={:new}
          title="New Household"
          action={@live_action}
          household={@household}
          current_user={@current_scope.user}
          patch={~p"/households"}
        />
      </.modal>
    </div>
    """
  end
end
