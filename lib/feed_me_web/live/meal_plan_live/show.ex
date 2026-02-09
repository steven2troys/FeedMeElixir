defmodule FeedMeWeb.MealPlanLive.Show do
  use FeedMeWeb, :live_view

  alias FeedMe.MealPlanning
  alias FeedMe.Procurement
  alias FeedMe.Recipes

  @meal_types [:breakfast, :lunch, :dinner, :snack]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    household = socket.assigns.household

    if connected?(socket), do: MealPlanning.subscribe(household.id)

    case MealPlanning.get_meal_plan_with_items(id, household.id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Meal plan not found")
         |> push_navigate(to: ~p"/households/#{household.id}/meal-plans")}

      meal_plan ->
        shopping_needs = MealPlanning.calculate_shopping_needs(meal_plan)

        {:ok,
         socket
         |> assign(:active_tab, :meal_plans)
         |> assign(:page_title, meal_plan.name)
         |> assign(:meal_plan, meal_plan)
         |> assign(:shopping_needs, shopping_needs)
         |> assign(:recipes, Recipes.list_recipes(household.id))
         |> assign(:recipe_search, "")
         |> assign(:adding_to, nil)
         |> assign(:editing_item, nil)}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    assign(socket, :page_title, socket.assigns.meal_plan.name)
  end

  defp apply_action(socket, :edit, _params) do
    assign(socket, :page_title, "Edit #{socket.assigns.meal_plan.name}")
  end

  @impl true
  def handle_event("add_item", %{"date" => date, "meal-type" => meal_type}, socket) do
    {:noreply, assign(socket, :adding_to, %{date: date, meal_type: meal_type})}
  end

  def handle_event("cancel_add", _params, socket) do
    {:noreply, assign(socket, adding_to: nil, recipe_search: "")}
  end

  def handle_event("search_recipes", %{"query" => query}, socket) do
    recipes =
      if query == "" do
        Recipes.list_recipes(socket.assigns.household.id)
      else
        Recipes.search_recipes(socket.assigns.household.id, query)
      end

    {:noreply, assign(socket, recipe_search: query, recipes: recipes)}
  end

  def handle_event("assign_recipe", %{"recipe-id" => recipe_id}, socket) do
    %{date: date, meal_type: meal_type} = socket.assigns.adding_to
    recipe = Recipes.get_recipe(recipe_id, socket.assigns.household.id)

    if recipe do
      attrs = %{
        date: date,
        meal_type: meal_type,
        title: recipe.title,
        servings: recipe.servings,
        meal_plan_id: socket.assigns.meal_plan.id,
        recipe_id: recipe.id,
        assigned_by_id: socket.assigns.current_scope.user.id
      }

      case MealPlanning.create_item(attrs) do
        {:ok, _item} ->
          {:noreply, socket |> reload_meal_plan() |> assign(adding_to: nil, recipe_search: "")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to add recipe")}
      end
    else
      {:noreply, put_flash(socket, :error, "Recipe not found")}
    end
  end

  def handle_event(
        "add_custom",
        %{"title" => title, "date" => date, "meal_type" => meal_type},
        socket
      ) do
    if String.trim(title) == "" do
      {:noreply, socket}
    else
      attrs = %{
        date: date,
        meal_type: meal_type,
        title: String.trim(title),
        meal_plan_id: socket.assigns.meal_plan.id,
        assigned_by_id: socket.assigns.current_scope.user.id
      }

      case MealPlanning.create_item(attrs) do
        {:ok, _item} ->
          {:noreply, socket |> reload_meal_plan() |> assign(adding_to: nil)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to add item")}
      end
    end
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    item = MealPlanning.get_item(id)

    if item do
      {:ok, _} = MealPlanning.delete_item(item)
      {:noreply, reload_meal_plan(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("activate_plan", _params, socket) do
    case MealPlanning.update_meal_plan(socket.assigns.meal_plan, %{
           status: :active,
           approved_by_id: socket.assigns.current_scope.user.id
         }) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meal plan activated")
         |> reload_meal_plan()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to activate plan")}
    end
  end

  def handle_event("complete_plan", _params, socket) do
    case MealPlanning.update_meal_plan(socket.assigns.meal_plan, %{status: :completed}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meal plan completed")
         |> reload_meal_plan()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to complete plan")}
    end
  end

  def handle_event("archive_plan", _params, socket) do
    case MealPlanning.update_meal_plan(socket.assigns.meal_plan, %{status: :archived}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meal plan archived")
         |> reload_meal_plan()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to archive plan")}
    end
  end

  def handle_event("generate_procurement", _params, socket) do
    case Procurement.create_from_meal_plan(
           socket.assigns.meal_plan,
           socket.assigns.current_scope.user
         ) do
      {:ok, :no_needs} ->
        {:noreply, put_flash(socket, :info, "No shopping needs for this meal plan")}

      {:ok, plan} ->
        {:noreply,
         socket
         |> put_flash(:info, "Procurement plan created")
         |> push_navigate(
           to: ~p"/households/#{socket.assigns.household.id}/procurement/#{plan.id}"
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create procurement plan")}
    end
  end

  def handle_event("add_to_shopping_list", _params, socket) do
    {:ok, %{added: added}} =
      MealPlanning.add_needs_to_shopping_list(
        socket.assigns.meal_plan,
        socket.assigns.current_scope.user
      )

    {:noreply, put_flash(socket, :info, "Added #{added} items to shopping list")}
  end

  def handle_event("validate_plan", %{"meal_plan" => params}, socket) do
    changeset =
      socket.assigns.meal_plan
      |> MealPlanning.change_meal_plan(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :edit_form, to_form(changeset))}
  end

  def handle_event("save_plan", %{"meal_plan" => params}, socket) do
    case MealPlanning.update_meal_plan(socket.assigns.meal_plan, params) do
      {:ok, _meal_plan} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meal plan updated")
         |> reload_meal_plan()
         |> push_patch(
           to:
             ~p"/households/#{socket.assigns.household.id}/meal-plans/#{socket.assigns.meal_plan.id}"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_info({:meal_plan_item_added, _}, socket), do: {:noreply, reload_meal_plan(socket)}
  def handle_info({:meal_plan_item_updated, _}, socket), do: {:noreply, reload_meal_plan(socket)}
  def handle_info({:meal_plan_item_deleted, _}, socket), do: {:noreply, reload_meal_plan(socket)}
  def handle_info({:meal_plan_updated, _}, socket), do: {:noreply, reload_meal_plan(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload_meal_plan(socket) do
    meal_plan =
      MealPlanning.get_meal_plan_with_items(
        socket.assigns.meal_plan.id,
        socket.assigns.household.id
      )

    shopping_needs = MealPlanning.calculate_shopping_needs(meal_plan)

    socket
    |> assign(:meal_plan, meal_plan)
    |> assign(:shopping_needs, shopping_needs)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :dates, MealPlanning.date_range(assigns.meal_plan))
    assigns = assign(assigns, :meal_types, @meal_types)
    assigns = assign(assigns, :items_by_date_meal, group_items(assigns.meal_plan.items))

    ~H"""
    <div class="mx-auto max-w-6xl">
      <.header>
        {@meal_plan.name}
        <:subtitle>
          {Calendar.strftime(@meal_plan.start_date, "%b %d")} - {Calendar.strftime(
            @meal_plan.end_date,
            "%b %d, %Y"
          )}
          <span class={["badge ml-2", status_badge_class(@meal_plan.status)]}>
            {@meal_plan.status}
          </span>
        </:subtitle>
        <:actions>
          <div class="flex gap-2">
            <%= if @meal_plan.status == :draft do %>
              <button phx-click="activate_plan" class="btn btn-primary btn-sm">
                <.icon name="hero-check" class="size-4" /> Activate
              </button>
            <% end %>
            <%= if @meal_plan.status == :active do %>
              <button phx-click="complete_plan" class="btn btn-success btn-sm">
                <.icon name="hero-check-circle" class="size-4" /> Complete
              </button>
            <% end %>
            <%= if @meal_plan.status in [:draft, :completed] do %>
              <button phx-click="archive_plan" class="btn btn-ghost btn-sm">Archive</button>
            <% end %>
            <.link
              patch={~p"/households/#{@household.id}/meal-plans/#{@meal_plan.id}/edit"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-pencil" class="size-4" /> Edit
            </.link>
          </div>
        </:actions>
      </.header>

      <div class="mt-6 flex flex-col lg:flex-row gap-6">
        <%!-- Calendar Grid --%>
        <div class="flex-1 overflow-x-auto">
          <table class="table table-sm w-full">
            <thead>
              <tr>
                <th class="w-24">Day</th>
                <%= for meal_type <- @meal_types do %>
                  <th class="text-center capitalize">{meal_type}</th>
                <% end %>
              </tr>
            </thead>
            <tbody>
              <%= for date <- @dates do %>
                <tr class={[is_today?(date) && "bg-primary/5"]}>
                  <td class="font-medium align-top py-3">
                    <div class="text-sm">{Calendar.strftime(date, "%a")}</div>
                    <div class="text-xs text-base-content/60">
                      {Calendar.strftime(date, "%b %d")}
                    </div>
                  </td>
                  <%= for meal_type <- @meal_types do %>
                    <td class="align-top py-3 min-w-[140px]">
                      <div class="space-y-1">
                        <%= for item <- get_items(@items_by_date_meal, date, meal_type) do %>
                          <div class="flex items-start gap-1 group">
                            <div class={[
                              "text-sm flex-1 rounded px-1.5 py-0.5",
                              item.recipe_id && "bg-base-200",
                              !item.recipe_id && "bg-base-200/50 italic"
                            ]}>
                              {item.title}
                              <%= if item.servings do %>
                                <span class="text-xs text-base-content/50">
                                  ({item.servings})
                                </span>
                              <% end %>
                            </div>
                            <button
                              phx-click="delete_item"
                              phx-value-id={item.id}
                              data-confirm="Remove this item?"
                              class="btn btn-ghost btn-xs opacity-0 group-hover:opacity-100 transition-opacity"
                            >
                              <.icon name="hero-x-mark" class="size-3" />
                            </button>
                          </div>
                        <% end %>
                        <button
                          phx-click="add_item"
                          phx-value-date={date}
                          phx-value-meal-type={meal_type}
                          class="btn btn-ghost btn-xs text-base-content/40 hover:text-primary w-full"
                        >
                          <.icon name="hero-plus" class="size-3" />
                        </button>
                      </div>
                    </td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <%!-- Sidebar: Shopping Needs --%>
        <div class="lg:w-72 space-y-4">
          <div class="card bg-base-100 border border-base-200">
            <div class="card-body p-4">
              <h3 class="card-title text-sm">
                <.icon name="hero-shopping-cart" class="size-4" /> Shopping Needs
              </h3>
              <%= if @shopping_needs == [] do %>
                <p class="text-sm text-base-content/60">
                  No additional items needed. Recipes use items already in your pantry.
                </p>
              <% else %>
                <ul class="space-y-1 mt-2">
                  <%= for need <- @shopping_needs do %>
                    <li class="text-sm flex justify-between">
                      <span>{need.name}</span>
                      <span class="text-base-content/60">
                        {format_quantity(need.need)} {need.unit}
                      </span>
                    </li>
                  <% end %>
                </ul>
                <button
                  phx-click="add_to_shopping_list"
                  class="btn btn-primary btn-sm mt-3 w-full"
                >
                  <.icon name="hero-shopping-cart" class="size-4" /> Add to Shopping List
                </button>
                <button
                  phx-click="generate_procurement"
                  class="btn btn-ghost btn-sm mt-1 w-full"
                >
                  <.icon name="hero-clipboard-document-list" class="size-4" />
                  Generate Procurement Plan
                </button>
              <% end %>
            </div>
          </div>

          <%= if @meal_plan.notes do %>
            <div class="card bg-base-100 border border-base-200">
              <div class="card-body p-4">
                <h3 class="card-title text-sm">Notes</h3>
                <p class="text-sm text-base-content/70">{@meal_plan.notes}</p>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <.back navigate={~p"/households/#{@household.id}/meal-plans"}>Back to meal plans</.back>

      <%!-- Add Item Modal --%>
      <.modal
        :if={@adding_to}
        id="add-item-modal"
        show
        on_cancel={JS.push("cancel_add")}
      >
        <.header>
          Add to {format_meal_type(@adding_to && @adding_to.meal_type)}
          <:subtitle>
            {format_add_date(@adding_to && @adding_to.date)}
          </:subtitle>
        </.header>

        <div class="mt-4 space-y-4">
          <%!-- Recipe Search --%>
          <div>
            <h4 class="font-medium text-sm mb-2">Choose a Recipe</h4>
            <form phx-change="search_recipes" phx-submit="search_recipes">
              <input
                type="text"
                name="query"
                value={@recipe_search}
                placeholder="Search recipes..."
                class="input input-bordered input-sm w-full"
                phx-debounce="300"
              />
            </form>
            <div class="mt-2 max-h-48 overflow-y-auto space-y-1">
              <%= for recipe <- Enum.take(@recipes, 10) do %>
                <button
                  phx-click="assign_recipe"
                  phx-value-recipe-id={recipe.id}
                  class="btn btn-ghost btn-sm w-full justify-start text-left"
                >
                  <span class="truncate">{recipe.title}</span>
                  <%= if recipe.servings do %>
                    <span class="badge badge-xs badge-ghost ml-auto">
                      {recipe.servings} servings
                    </span>
                  <% end %>
                </button>
              <% end %>
            </div>
          </div>

          <div class="divider text-xs">OR</div>

          <%!-- Custom Entry --%>
          <div>
            <h4 class="font-medium text-sm mb-2">Custom Entry</h4>
            <form phx-submit="add_custom">
              <input type="hidden" name="date" value={@adding_to && @adding_to.date} />
              <input type="hidden" name="meal_type" value={@adding_to && @adding_to.meal_type} />
              <div class="flex gap-2">
                <input
                  type="text"
                  name="title"
                  placeholder="e.g., Leftovers, Eat out..."
                  class="input input-bordered input-sm flex-1"
                />
                <button type="submit" class="btn btn-sm btn-primary">Add</button>
              </div>
            </form>
          </div>
        </div>
      </.modal>

      <%!-- Edit Plan Modal --%>
      <.modal
        :if={@live_action == :edit}
        id="edit-plan-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@household.id}/meal-plans/#{@meal_plan.id}")}
      >
        <.header>Edit Meal Plan</.header>

        <.simple_form
          for={to_form(MealPlanning.change_meal_plan(@meal_plan, %{}))}
          phx-change="validate_plan"
          phx-submit="save_plan"
          id="edit-plan-form"
        >
          <.input
            field={to_form(MealPlanning.change_meal_plan(@meal_plan, %{}))[:name]}
            type="text"
            label="Name"
            name="meal_plan[name]"
            value={@meal_plan.name}
          />
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={to_form(MealPlanning.change_meal_plan(@meal_plan, %{}))[:start_date]}
              type="date"
              label="Start Date"
              name="meal_plan[start_date]"
              value={@meal_plan.start_date}
            />
            <.input
              field={to_form(MealPlanning.change_meal_plan(@meal_plan, %{}))[:end_date]}
              type="date"
              label="End Date"
              name="meal_plan[end_date]"
              value={@meal_plan.end_date}
            />
          </div>
          <.input
            field={to_form(MealPlanning.change_meal_plan(@meal_plan, %{}))[:notes]}
            type="textarea"
            label="Notes"
            name="meal_plan[notes]"
            value={@meal_plan.notes}
          />
          <:actions>
            <.button phx-disable-with="Saving...">Save Changes</.button>
          </:actions>
        </.simple_form>
      </.modal>
    </div>
    """
  end

  defp group_items(items) do
    Enum.group_by(items, fn item -> {item.date, item.meal_type} end)
  end

  defp get_items(items_map, date, meal_type) do
    Map.get(items_map, {date, meal_type}, [])
  end

  defp is_today?(date), do: date == Date.utc_today()

  defp status_badge_class(:draft), do: "badge-ghost"
  defp status_badge_class(:active), do: "badge-primary"
  defp status_badge_class(:completed), do: "badge-success"
  defp status_badge_class(:archived), do: "badge-neutral"
  defp status_badge_class(_), do: "badge-ghost"

  defp format_meal_type(nil), do: ""
  defp format_meal_type(type) when is_binary(type), do: String.capitalize(type)

  defp format_meal_type(type) when is_atom(type),
    do: type |> Atom.to_string() |> String.capitalize()

  defp format_add_date(nil), do: ""

  defp format_add_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> Calendar.strftime(d, "%A, %b %d")
      _ -> date
    end
  end

  defp format_add_date(%Date{} = date), do: Calendar.strftime(date, "%A, %b %d")

  defp format_quantity(decimal) do
    decimal
    |> Decimal.round(1)
    |> Decimal.to_string(:normal)
    |> String.replace(~r/\.0$/, "")
  end
end
