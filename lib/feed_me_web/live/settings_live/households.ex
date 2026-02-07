defmodule FeedMeWeb.SettingsLive.Households do
  use FeedMeWeb, :live_view

  alias FeedMe.Households
  alias FeedMe.Households.Household

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    households = Households.list_households_for_user(user)

    {:ok,
     socket
     |> assign(:active_tab, :settings)
     |> assign(:page_title, "My Households")
     |> assign(:households, households)
     |> assign(:current_household_id, socket.assigns.household.id)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, :new_household, %Household{})
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :new_household, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    if Households.admin?(user, id) do
      household = Households.get_household(id)
      {:ok, _} = Households.delete_household(household)
      households = Households.list_households_for_user(user)

      if id == socket.assigns.current_household_id do
        {:noreply,
         socket
         |> put_flash(:info, "Household deleted")
         |> push_navigate(to: ~p"/")}
      else
        {:noreply,
         socket
         |> put_flash(:info, "Household deleted")
         |> assign(:households, households)}
      end
    else
      {:noreply, put_flash(socket, :error, "Only admins can delete households")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        My Households
        <:subtitle>Switch between or manage your households</:subtitle>
        <:actions>
          <.link patch={~p"/households/#{@current_household_id}/settings/households/new"}>
            <.button>New Household</.button>
          </.link>
        </:actions>
      </.header>

      <div class="mt-6 grid gap-4 sm:grid-cols-2">
        <%= for %{household: household, role: role} <- @households do %>
          <div class={[
            "card border transition-all",
            if(household.id == @current_household_id,
              do: "bg-primary/5 border-primary",
              else: "bg-base-100 border-base-200 hover:border-primary/50 hover:shadow-md"
            )
          ]}>
            <div class="card-body p-4">
              <div class="flex items-start justify-between">
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2">
                    <h3 class="font-semibold truncate">{household.name}</h3>
                    <%= if household.id == @current_household_id do %>
                      <span class="badge badge-primary badge-sm">Current</span>
                    <% end %>
                  </div>
                  <span class={[
                    "badge badge-sm mt-1",
                    role == :admin && "badge-primary badge-outline",
                    role == :member && "badge-neutral badge-outline"
                  ]}>
                    {role}
                  </span>
                </div>

                <div class="flex items-center gap-1">
                  <%= if household.id != @current_household_id do %>
                    <.link
                      navigate={~p"/households/#{household.id}"}
                      class="btn btn-ghost btn-sm"
                      title="Switch to this household"
                    >
                      <.icon name="hero-arrow-right-circle" class="size-5" />
                    </.link>
                  <% end %>
                  <%= if role == :admin do %>
                    <button
                      phx-click="delete"
                      phx-value-id={household.id}
                      data-confirm="Are you sure you want to delete this household? This cannot be undone."
                      class="btn btn-ghost btn-sm text-error"
                      title="Delete household"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <div class="mt-6">
        <.back navigate={~p"/households/#{@current_household_id}/settings"}>
          Back to settings
        </.back>
      </div>

      <.modal
        :if={@live_action == :new}
        id="new-household-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@current_household_id}/settings/households")}
      >
        <.live_component
          module={FeedMeWeb.HouseholdLive.FormComponent}
          id={:new}
          title="New Household"
          action={:new}
          household={@new_household}
          current_user={@current_scope.user}
          patch={~p"/households/#{@current_household_id}/settings/households"}
        />
      </.modal>
    </div>
    """
  end
end
