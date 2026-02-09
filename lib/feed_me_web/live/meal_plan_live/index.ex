defmodule FeedMeWeb.MealPlanLive.Index do
  use FeedMeWeb, :live_view

  alias FeedMe.MealPlanning
  alias FeedMe.MealPlanning.MealPlan

  @impl true
  def mount(_params, _session, socket) do
    household = socket.assigns.household

    if connected?(socket), do: MealPlanning.subscribe(household.id)

    meal_plans = MealPlanning.list_meal_plans(household.id)

    {:ok,
     socket
     |> assign(:active_tab, :meal_plans)
     |> assign(:meal_plans, meal_plans)
     |> assign(:filter_status, nil)
     |> assign(:page_title, "Meal Plans")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Meal Plans")
    |> assign(:meal_plan, nil)
  end

  defp apply_action(socket, :new, _params) do
    today = Date.utc_today()
    # Default to a week starting next Monday
    days_until_monday = rem(8 - Date.day_of_week(today), 7)
    days_until_monday = if days_until_monday == 0, do: 7, else: days_until_monday
    start = Date.add(today, days_until_monday)
    end_date = Date.add(start, 6)

    socket
    |> assign(:page_title, "New Meal Plan")
    |> assign(
      :meal_plan,
      %MealPlan{
        household_id: socket.assigns.household.id,
        start_date: start,
        end_date: end_date
      }
    )
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    meal_plan = MealPlanning.get_meal_plan(id, socket.assigns.household.id)

    if meal_plan do
      {:ok, _} = MealPlanning.delete_meal_plan(meal_plan)

      {:noreply,
       socket
       |> put_flash(:info, "Meal plan deleted")
       |> assign(:meal_plans, MealPlanning.list_meal_plans(socket.assigns.household.id))}
    else
      {:noreply, put_flash(socket, :error, "Meal plan not found")}
    end
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    status = if status == "", do: nil, else: String.to_existing_atom(status)
    opts = if status, do: [status: status], else: []
    meal_plans = MealPlanning.list_meal_plans(socket.assigns.household.id, opts)

    {:noreply, assign(socket, filter_status: status, meal_plans: meal_plans)}
  end

  def handle_event("validate", %{"meal_plan" => params}, socket) do
    changeset =
      socket.assigns.meal_plan
      |> MealPlanning.change_meal_plan(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"meal_plan" => params}, socket) do
    params =
      params
      |> Map.put("household_id", socket.assigns.household.id)
      |> Map.put("created_by_id", socket.assigns.current_scope.user.id)

    case MealPlanning.create_meal_plan(params) do
      {:ok, meal_plan} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meal plan created")
         |> push_navigate(
           to: ~p"/households/#{socket.assigns.household.id}/meal-plans/#{meal_plan.id}"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_info({:meal_plan_created, _}, socket) do
    {:noreply, reload_plans(socket)}
  end

  def handle_info({:meal_plan_updated, _}, socket) do
    {:noreply, reload_plans(socket)}
  end

  def handle_info({:meal_plan_deleted, _}, socket) do
    {:noreply, reload_plans(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload_plans(socket) do
    opts = if socket.assigns.filter_status, do: [status: socket.assigns.filter_status], else: []
    assign(socket, :meal_plans, MealPlanning.list_meal_plans(socket.assigns.household.id, opts))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        Meal Plans
        <:subtitle>{@household.name}</:subtitle>
        <:actions>
          <.link patch={~p"/households/#{@household.id}/meal-plans/new"}>
            <.button>New Plan</.button>
          </.link>
        </:actions>
      </.header>

      <div class="mt-6">
        <form phx-change="filter_status">
          <select name="status" class="select select-bordered select-sm">
            <option value="">All Statuses</option>
            <option value="draft" selected={@filter_status == :draft}>Draft</option>
            <option value="active" selected={@filter_status == :active}>Active</option>
            <option value="completed" selected={@filter_status == :completed}>Completed</option>
            <option value="archived" selected={@filter_status == :archived}>Archived</option>
          </select>
        </form>
      </div>

      <div class="mt-6">
        <%= if @meal_plans == [] do %>
          <div class="text-center py-12 bg-base-200 rounded-lg">
            <.icon name="hero-calendar-days" class="size-12 mx-auto text-base-content/50" />
            <p class="mt-2 text-base-content/70">No meal plans yet.</p>
            <.link
              patch={~p"/households/#{@household.id}/meal-plans/new"}
              class="btn btn-primary mt-4"
            >
              Create your first meal plan
            </.link>
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for plan <- @meal_plans do %>
              <.link
                navigate={~p"/households/#{@household.id}/meal-plans/#{plan.id}"}
                class="card bg-base-100 border border-base-200 hover:border-primary transition-colors block"
              >
                <div class="card-body p-4 flex-row items-center justify-between">
                  <div>
                    <h3 class="font-semibold">{plan.name}</h3>
                    <p class="text-sm text-base-content/60">
                      {Calendar.strftime(plan.start_date, "%b %d")} - {Calendar.strftime(
                        plan.end_date,
                        "%b %d, %Y"
                      )}
                    </p>
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
        id="meal-plan-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@household.id}/meal-plans")}
      >
        <.header>New Meal Plan</.header>

        <.simple_form
          for={@meal_plan && to_form(MealPlanning.change_meal_plan(@meal_plan, %{}))}
          phx-change="validate"
          phx-submit="save"
          id="meal-plan-form"
        >
          <.input
            field={to_form(MealPlanning.change_meal_plan(@meal_plan || %MealPlan{}, %{}))[:name]}
            type="text"
            label="Name"
            placeholder="Week of Feb 10"
            name="meal_plan[name]"
            value={default_plan_name(@meal_plan)}
          />
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={
                to_form(MealPlanning.change_meal_plan(@meal_plan || %MealPlan{}, %{}))[:start_date]
              }
              type="date"
              label="Start Date"
              name="meal_plan[start_date]"
              value={@meal_plan && @meal_plan.start_date}
            />
            <.input
              field={
                to_form(MealPlanning.change_meal_plan(@meal_plan || %MealPlan{}, %{}))[:end_date]
              }
              type="date"
              label="End Date"
              name="meal_plan[end_date]"
              value={@meal_plan && @meal_plan.end_date}
            />
          </div>
          <:actions>
            <.button phx-disable-with="Creating...">Create Plan</.button>
          </:actions>
        </.simple_form>
      </.modal>
    </div>
    """
  end

  defp status_badge_class(:draft), do: "badge-ghost"
  defp status_badge_class(:active), do: "badge-primary"
  defp status_badge_class(:completed), do: "badge-success"
  defp status_badge_class(:archived), do: "badge-neutral"
  defp status_badge_class(_), do: "badge-ghost"

  defp default_plan_name(nil), do: ""

  defp default_plan_name(%MealPlan{start_date: start_date}) when not is_nil(start_date) do
    "Week of #{Calendar.strftime(start_date, "%b %d")}"
  end

  defp default_plan_name(_), do: ""
end
