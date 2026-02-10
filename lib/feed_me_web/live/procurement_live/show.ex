defmodule FeedMeWeb.ProcurementLive.Show do
  use FeedMeWeb, :live_view

  alias FeedMe.Procurement

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    household = socket.assigns.household

    if connected?(socket), do: Procurement.subscribe(household.id)

    case Procurement.get_plan_with_items(id, household.id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Procurement plan not found")
         |> push_navigate(to: ~p"/households/#{household.id}/procurement")}

      plan ->
        budget_check = Procurement.check_budget(plan)

        {:ok,
         socket
         |> assign(:active_tab, :procurement)
         |> assign(:page_title, plan.name)
         |> assign(:plan, plan)
         |> assign(:budget_check, budget_check)}
    end
  end

  @impl true
  def handle_event("approve", _params, socket) do
    case Procurement.approve_plan(socket.assigns.plan, socket.assigns.current_scope.user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Plan approved")
         |> reload_plan()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve plan")}
    end
  end

  def handle_event("mark_shopping", _params, socket) do
    case Procurement.mark_shopping(socket.assigns.plan) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Marked as shopping")
         |> reload_plan()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  def handle_event("fulfill", _params, socket) do
    case Procurement.fulfill_plan(socket.assigns.plan) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Plan fulfilled")
         |> reload_plan()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to fulfill plan")}
    end
  end

  def handle_event("cancel", _params, socket) do
    case Procurement.cancel_plan(socket.assigns.plan) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Plan cancelled")
         |> reload_plan()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel plan")}
    end
  end

  def handle_event("sync_to_shopping_list", _params, socket) do
    {:ok, %{added: added}} =
      Procurement.sync_to_shopping_list(
        socket.assigns.plan,
        socket.assigns.current_scope.user
      )

    {:noreply,
     socket
     |> put_flash(:info, "Added #{added} items to shopping list")
     |> reload_plan()}
  end

  def handle_event("mark_item_purchased", %{"id" => id}, socket) do
    item = Procurement.get_item(id)

    if item do
      Procurement.update_item(item, %{status: :purchased})
      {:noreply, reload_plan(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_item_skipped", %{"id" => id}, socket) do
    item = Procurement.get_item(id)

    if item do
      Procurement.update_item(item, %{status: :skipped})
      {:noreply, reload_plan(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_actual_price", %{"id" => id, "price" => price}, socket) do
    item = Procurement.get_item(id)

    if item && price != "" do
      Procurement.update_item(item, %{actual_price: price})
      {:noreply, reload_plan(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_item", %{"name" => name}, socket) do
    if String.trim(name) != "" do
      Procurement.create_item(%{
        name: String.trim(name),
        procurement_plan_id: socket.assigns.plan.id
      })

      {:noreply, reload_plan(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Procurement.get_item(id)
    if item, do: Procurement.delete_item(item)
    {:noreply, reload_plan(socket)}
  end

  @impl true
  def handle_info({:procurement_plan_updated, _}, socket), do: {:noreply, reload_plan(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload_plan(socket) do
    plan =
      Procurement.get_plan_with_items(
        socket.assigns.plan.id,
        socket.assigns.household.id
      )

    budget_check = Procurement.check_budget(plan)

    socket
    |> assign(:plan, plan)
    |> assign(:budget_check, budget_check)
  end

  @impl true
  def render(assigns) do
    grouped_items = Enum.group_by(assigns.plan.items, & &1.category)
    assigns = assign(assigns, :grouped_items, grouped_items)

    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        {@plan.name}
        <:subtitle>
          <span class={["badge", status_badge_class(@plan.status)]}>{@plan.status}</span>
          <span class="text-sm text-base-content/60 ml-2 capitalize">
            {format_source(@plan.source)}
          </span>
        </:subtitle>
        <:actions>
          <div class="flex gap-2 flex-wrap">
            <%= if @plan.status == :suggested do %>
              <button phx-click="approve" class="btn btn-primary btn-sm">
                <.icon name="hero-check" class="size-4" /> Approve
              </button>
            <% end %>
            <%= if @plan.status == :approved do %>
              <button phx-click="mark_shopping" class="btn btn-primary btn-sm">
                <.icon name="hero-shopping-bag" class="size-4" /> Start Shopping
              </button>
              <button phx-click="sync_to_shopping_list" class="btn btn-ghost btn-sm">
                <.icon name="hero-shopping-cart" class="size-4" /> Add to Shopping List
              </button>
            <% end %>
            <%= if @plan.status == :shopping do %>
              <button phx-click="fulfill" class="btn btn-success btn-sm">
                <.icon name="hero-check-circle" class="size-4" /> Mark Fulfilled
              </button>
            <% end %>
            <%= if @plan.status in [:suggested, :approved] do %>
              <button phx-click="cancel" class="btn btn-ghost btn-sm" data-confirm="Cancel this plan?">
                Cancel
              </button>
            <% end %>
          </div>
        </:actions>
      </.header>

      <div class="mt-6 flex flex-col lg:flex-row gap-6">
        <%!-- Items List --%>
        <div class="flex-1">
          <%= if @plan.items == [] do %>
            <div class="text-center py-8 bg-base-200 rounded-lg">
              <p class="text-base-content/60">No items in this plan yet.</p>
            </div>
          <% else %>
            <%= for {category, items} <- @grouped_items do %>
              <div class="mb-4">
                <%= if category do %>
                  <h3 class="font-medium text-sm text-base-content/60 mb-2 uppercase">
                    {category}
                  </h3>
                <% end %>
                <div class="space-y-2">
                  <%= for item <- items do %>
                    <div class={[
                      "flex items-center gap-3 p-3 rounded-lg border",
                      item.status == :purchased && "bg-success/10 border-success/30",
                      item.status == :skipped && "bg-base-200 border-base-300 opacity-60",
                      item.status in [:needed, :in_cart] && "bg-base-100 border-base-200"
                    ]}>
                      <div class="flex-1">
                        <div class="flex items-center gap-2">
                          <span class={[
                            "font-medium",
                            item.status == :skipped && "line-through"
                          ]}>
                            {item.name}
                          </span>
                          <%= if item.quantity do %>
                            <span class="text-sm text-base-content/60">
                              {format_quantity(item.quantity)} {item.unit}
                            </span>
                          <% end %>
                        </div>
                        <div class="flex items-center gap-2 mt-1">
                          <%= if item.estimated_price do %>
                            <span class="text-xs text-base-content/50">
                              Est. ${Decimal.round(item.estimated_price, 2)}
                            </span>
                          <% end %>
                          <%= if item.supplier do %>
                            <span class="badge badge-xs badge-ghost">
                              {item.supplier.name}
                            </span>
                          <% end %>
                          <%= if item.notes do %>
                            <span class="text-xs text-base-content/50">{item.notes}</span>
                          <% end %>
                        </div>
                      </div>

                      <div class="flex items-center gap-1">
                        <%= if item.deep_link_url do %>
                          <a
                            href={item.deep_link_url}
                            target="_blank"
                            rel="noopener"
                            class="btn btn-ghost btn-xs"
                          >
                            <.icon name="hero-arrow-top-right-on-square" class="size-3" />
                          </a>
                        <% end %>

                        <%= if @plan.status in [:shopping, :approved] do %>
                          <%= if item.status == :needed do %>
                            <button
                              phx-click="mark_item_purchased"
                              phx-value-id={item.id}
                              class="btn btn-ghost btn-xs text-success"
                            >
                              <.icon name="hero-check" class="size-4" />
                            </button>
                            <button
                              phx-click="mark_item_skipped"
                              phx-value-id={item.id}
                              class="btn btn-ghost btn-xs text-base-content/40"
                            >
                              <.icon name="hero-x-mark" class="size-4" />
                            </button>
                          <% end %>
                        <% end %>

                        <%= if @plan.status == :suggested do %>
                          <button
                            phx-click="delete_item"
                            phx-value-id={item.id}
                            class="btn btn-ghost btn-xs text-error"
                          >
                            <.icon name="hero-trash" class="size-3" />
                          </button>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          <% end %>

          <%!-- Add Item --%>
          <%= if @plan.status in [:suggested, :approved] do %>
            <form phx-submit="add_item" class="mt-4 flex gap-2">
              <input
                type="text"
                name="name"
                placeholder="Add item..."
                class="input input-bordered input-sm flex-1"
              />
              <button type="submit" class="btn btn-ghost btn-sm">
                <.icon name="hero-plus" class="size-4" />
              </button>
            </form>
          <% end %>
        </div>

        <%!-- Sidebar --%>
        <div class="lg:w-64 space-y-4">
          <div class="card bg-base-100 border border-base-200">
            <div class="card-body p-4">
              <h3 class="card-title text-sm">Summary</h3>
              <div class="space-y-2 text-sm">
                <div class="flex justify-between">
                  <span class="text-base-content/60">Items</span>
                  <span>{@budget_check.item_count}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-base-content/60">Estimated Total</span>
                  <span class="font-medium">
                    ${Decimal.round(@budget_check.estimated_total, 2)}
                  </span>
                </div>
                <%= if @plan.actual_total do %>
                  <div class="flex justify-between">
                    <span class="text-base-content/60">Actual Total</span>
                    <span class="font-medium">
                      ${Decimal.round(@plan.actual_total, 2)}
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <%= if @plan.notes do %>
            <div class="card bg-base-100 border border-base-200">
              <div class="card-body p-4">
                <h3 class="card-title text-sm">Notes</h3>
                <p class="text-sm text-base-content/70">{@plan.notes}</p>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <.back navigate={~p"/households/#{@household.id}/procurement"}>Back to procurement</.back>
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

  defp format_quantity(decimal) do
    decimal
    |> Decimal.round(1)
    |> Decimal.to_string(:normal)
    |> String.replace(~r/\.0$/, "")
  end
end
