defmodule FeedMeWeb.ProcurementLive.Index do
  use FeedMeWeb, :live_view

  alias FeedMe.Procurement
  alias FeedMe.Procurement.ProcurementPlan
  alias FeedMe.MealPlanning

  @impl true
  def mount(_params, _session, socket) do
    household = socket.assigns.household

    if connected?(socket), do: Procurement.subscribe(household.id)

    plans = Procurement.list_plans(household.id)
    meal_plans = MealPlanning.list_meal_plans(household.id, status: :active)

    {:ok,
     socket
     |> assign(:active_tab, :procurement)
     |> assign(:plans, plans)
     |> assign(:meal_plans, meal_plans)
     |> assign(:filter_status, nil)
     |> assign(:page_title, "Procurement")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Procurement")
    |> assign(:plan, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Procurement Plan")
    |> assign(:plan, %ProcurementPlan{household_id: socket.assigns.household.id})
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    plan = Procurement.get_plan(id, socket.assigns.household.id)

    if plan do
      {:ok, _} = Procurement.delete_plan(plan)

      {:noreply,
       socket
       |> put_flash(:info, "Procurement plan deleted")
       |> reload_plans()}
    else
      {:noreply, put_flash(socket, :error, "Plan not found")}
    end
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    status = if status == "", do: nil, else: String.to_existing_atom(status)
    opts = if status, do: [status: status], else: []
    plans = Procurement.list_plans(socket.assigns.household.id, opts)

    {:noreply, assign(socket, filter_status: status, plans: plans)}
  end

  def handle_event("create_manual", %{"name" => name}, socket) do
    attrs = %{
      name: name,
      household_id: socket.assigns.household.id,
      created_by_id: socket.assigns.current_scope.user.id,
      source: :manual,
      status: :suggested
    }

    case Procurement.create_plan(attrs) do
      {:ok, plan} ->
        {:noreply,
         socket
         |> put_flash(:info, "Plan created")
         |> push_navigate(
           to: ~p"/households/#{socket.assigns.household.id}/procurement/#{plan.id}"
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create plan")}
    end
  end

  def handle_event("create_from_meal_plan", %{"meal-plan-id" => meal_plan_id}, socket) do
    meal_plan = MealPlanning.get_meal_plan_with_items(meal_plan_id, socket.assigns.household.id)

    if meal_plan do
      case Procurement.create_from_meal_plan(meal_plan, socket.assigns.current_scope.user) do
        {:ok, :no_needs} ->
          {:noreply, put_flash(socket, :info, "No shopping needs for this meal plan")}

        {:ok, plan} ->
          {:noreply,
           socket
           |> put_flash(:info, "Procurement plan created from meal plan")
           |> push_navigate(
             to: ~p"/households/#{socket.assigns.household.id}/procurement/#{plan.id}"
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to create procurement plan")}
      end
    else
      {:noreply, put_flash(socket, :error, "Meal plan not found")}
    end
  end

  def handle_event("create_from_restock", _params, socket) do
    case Procurement.create_from_restock(
           socket.assigns.household.id,
           socket.assigns.current_scope.user
         ) do
      {:ok, :no_needs} ->
        {:noreply, put_flash(socket, :info, "No items need restocking")}

      {:ok, plan} ->
        {:noreply,
         socket
         |> put_flash(:info, "Restock plan created")
         |> push_navigate(
           to: ~p"/households/#{socket.assigns.household.id}/procurement/#{plan.id}"
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create restock plan")}
    end
  end

  @impl true
  def handle_info({:procurement_plan_created, _}, socket), do: {:noreply, reload_plans(socket)}
  def handle_info({:procurement_plan_updated, _}, socket), do: {:noreply, reload_plans(socket)}
  def handle_info({:procurement_plan_deleted, _}, socket), do: {:noreply, reload_plans(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload_plans(socket) do
    opts = if socket.assigns.filter_status, do: [status: socket.assigns.filter_status], else: []
    assign(socket, :plans, Procurement.list_plans(socket.assigns.household.id, opts))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        Procurement
        <:subtitle>Plan and track your grocery purchases</:subtitle>
        <:actions>
          <.link patch={~p"/households/#{@household.id}/procurement/new"}>
            <.button>New Plan</.button>
          </.link>
        </:actions>
      </.header>

      <div class="mt-6">
        <form phx-change="filter_status">
          <select name="status" class="select select-bordered select-sm">
            <option value="">All Statuses</option>
            <option value="suggested" selected={@filter_status == :suggested}>Suggested</option>
            <option value="approved" selected={@filter_status == :approved}>Approved</option>
            <option value="shopping" selected={@filter_status == :shopping}>Shopping</option>
            <option value="fulfilled" selected={@filter_status == :fulfilled}>Fulfilled</option>
            <option value="cancelled" selected={@filter_status == :cancelled}>Cancelled</option>
          </select>
        </form>
      </div>

      <div class="mt-6">
        <%= if @plans == [] do %>
          <div class="text-center py-12 bg-base-200 rounded-lg">
            <.icon name="hero-clipboard-document-list" class="size-12 mx-auto text-base-content/50" />
            <p class="mt-2 text-base-content/70">No procurement plans yet.</p>
            <.link
              patch={~p"/households/#{@household.id}/procurement/new"}
              class="btn btn-primary mt-4"
            >
              Create your first plan
            </.link>
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for plan <- @plans do %>
              <.link
                navigate={~p"/households/#{@household.id}/procurement/#{plan.id}"}
                class="card bg-base-100 border border-base-200 hover:border-primary transition-colors block"
              >
                <div class="card-body p-4 flex-row items-center justify-between">
                  <div>
                    <h3 class="font-semibold">{plan.name}</h3>
                    <div class="flex items-center gap-2 mt-1">
                      <span class="text-sm text-base-content/60 capitalize">
                        {format_source(plan.source)}
                      </span>
                      <%= if plan.estimated_total do %>
                        <span class="text-sm text-base-content/60">
                          Est. ${Decimal.round(plan.estimated_total, 2)}
                        </span>
                      <% end %>
                    </div>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class={["badge", status_badge_class(plan.status)]}>
                      {plan.status}
                    </span>
                    <%= if plan.ai_generated do %>
                      <span class="badge badge-outline badge-sm">AI</span>
                    <% end %>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>

      <.back navigate={~p"/households/#{@household.id}"}>Back to household</.back>

      <.modal
        :if={@live_action == :new}
        id="new-plan-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@household.id}/procurement")}
      >
        <.header>New Procurement Plan</.header>

        <div class="mt-4 space-y-4">
          <%!-- From Meal Plan --%>
          <%= if @meal_plans != [] do %>
            <div>
              <h4 class="font-medium text-sm mb-2">From Meal Plan</h4>
              <div class="space-y-1">
                <%= for mp <- @meal_plans do %>
                  <button
                    phx-click="create_from_meal_plan"
                    phx-value-meal-plan-id={mp.id}
                    class="btn btn-ghost btn-sm w-full justify-start"
                  >
                    <.icon name="hero-calendar-days" class="size-4" />
                    {mp.name}
                  </button>
                <% end %>
              </div>
            </div>
            <div class="divider text-xs">OR</div>
          <% end %>

          <%!-- From Restock --%>
          <button phx-click="create_from_restock" class="btn btn-ghost btn-sm w-full justify-start">
            <.icon name="hero-arrow-path" class="size-4" /> From Restock Needs
          </button>

          <div class="divider text-xs">OR</div>

          <%!-- Manual --%>
          <div>
            <h4 class="font-medium text-sm mb-2">Manual Plan</h4>
            <form phx-submit="create_manual" class="flex gap-2">
              <input
                type="text"
                name="name"
                placeholder="Plan name..."
                class="input input-bordered input-sm flex-1"
                required
              />
              <button type="submit" class="btn btn-primary btn-sm">Create</button>
            </form>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  defp status_badge_class(:suggested), do: "badge-warning"
  defp status_badge_class(:approved), do: "badge-info"
  defp status_badge_class(:shopping), do: "badge-primary"
  defp status_badge_class(:fulfilled), do: "badge-success"
  defp status_badge_class(:cancelled), do: "badge-neutral"
  defp status_badge_class(_), do: "badge-ghost"

  defp format_source(:meal_plan), do: "From meal plan"
  defp format_source(:restock), do: "Restock"
  defp format_source(:expiring), do: "Expiring items"
  defp format_source(:manual), do: "Manual"
  defp format_source(_), do: ""
end
