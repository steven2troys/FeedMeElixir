defmodule FeedMeWeb.SettingsLive.Suppliers do
  use FeedMeWeb, :live_view

  alias FeedMe.Suppliers
  alias FeedMe.Suppliers.Supplier

  @impl true
  def mount(_params, _session, socket) do
    household = socket.assigns.household
    system_suppliers = Suppliers.list_suppliers()
    custom_suppliers = Suppliers.list_custom_suppliers(household.id)
    enabled = Suppliers.list_household_suppliers(household.id)
    enabled_ids = MapSet.new(enabled, & &1.supplier_id)

    {:ok,
     socket
     |> assign(:active_tab, :settings)
     |> assign(:page_title, "Suppliers")
     |> assign(:system_suppliers, system_suppliers)
     |> assign(:custom_suppliers, custom_suppliers)
     |> assign(:enabled_ids, enabled_ids)
     |> assign(:household_suppliers, enabled)
     |> assign(:adding_custom, false)
     |> assign(:custom_form, to_form(Suppliers.change_supplier(%Supplier{})))}
  end

  @impl true
  def handle_event("toggle_supplier", %{"id" => supplier_id}, socket) do
    household = socket.assigns.household
    user = socket.assigns.current_scope.user

    if MapSet.member?(socket.assigns.enabled_ids, supplier_id) do
      hs = Suppliers.get_household_supplier(household.id, supplier_id)
      if hs, do: Suppliers.disable_supplier(hs)
    else
      Suppliers.enable_supplier(household.id, supplier_id, user)
    end

    {:noreply, reload_suppliers(socket)}
  end

  def handle_event("set_default", %{"id" => supplier_id}, socket) do
    Suppliers.set_default_supplier(socket.assigns.household.id, supplier_id)
    {:noreply, reload_suppliers(socket)}
  end

  def handle_event("show_add_custom", _params, socket) do
    {:noreply, assign(socket, adding_custom: true)}
  end

  def handle_event("cancel_add_custom", _params, socket) do
    {:noreply,
     assign(socket,
       adding_custom: false,
       custom_form: to_form(Suppliers.change_supplier(%Supplier{}))
     )}
  end

  def handle_event("validate_custom", %{"supplier" => params}, socket) do
    changeset =
      %Supplier{}
      |> Suppliers.change_supplier(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :custom_form, to_form(changeset))}
  end

  def handle_event("save_custom", %{"supplier" => params}, socket) do
    household = socket.assigns.household
    user = socket.assigns.current_scope.user

    params =
      params
      |> Map.put("household_id", household.id)
      |> Map.put("code", "custom_#{Ecto.UUID.generate()}")
      |> Map.put("is_active", "true")

    case Suppliers.create_supplier(params) do
      {:ok, supplier} ->
        # Auto-enable the custom supplier
        Suppliers.enable_supplier(household.id, supplier.id, user)

        {:noreply,
         socket
         |> put_flash(:info, "Custom supplier added")
         |> assign(adding_custom: false)
         |> reload_suppliers()
         |> assign(:custom_form, to_form(Suppliers.change_supplier(%Supplier{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :custom_form, to_form(changeset))}
    end
  end

  def handle_event("delete_custom", %{"id" => id}, socket) do
    supplier = Suppliers.get_supplier(id)

    if supplier && supplier.household_id == socket.assigns.household.id do
      Suppliers.delete_supplier(supplier)

      {:noreply,
       socket
       |> put_flash(:info, "Supplier deleted")
       |> reload_suppliers()}
    else
      {:noreply, put_flash(socket, :error, "Supplier not found")}
    end
  end

  defp reload_suppliers(socket) do
    household = socket.assigns.household
    custom_suppliers = Suppliers.list_custom_suppliers(household.id)
    enabled = Suppliers.list_household_suppliers(household.id)
    enabled_ids = MapSet.new(enabled, & &1.supplier_id)

    socket
    |> assign(:custom_suppliers, custom_suppliers)
    |> assign(:enabled_ids, enabled_ids)
    |> assign(:household_suppliers, enabled)
  end

  @impl true
  def render(assigns) do
    default_hs =
      Enum.find(assigns.household_suppliers, & &1.is_default)

    assigns = assign(assigns, :default_supplier_id, default_hs && default_hs.supplier_id)

    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        Suppliers
        <:subtitle>Manage grocery suppliers for your household</:subtitle>
      </.header>

      <div class="mt-6 space-y-6">
        <%!-- System Suppliers --%>
        <div class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="card-title text-base">Available Suppliers</h3>
            <p class="text-sm text-base-content/60">
              Enable suppliers your household shops with.
            </p>
            <div class="space-y-2 mt-3">
              <%= for supplier <- @system_suppliers do %>
                <div class="flex items-center justify-between py-2">
                  <div class="flex items-center gap-3">
                    <input
                      type="checkbox"
                      class="toggle toggle-sm toggle-primary"
                      checked={MapSet.member?(@enabled_ids, supplier.id)}
                      phx-click="toggle_supplier"
                      phx-value-id={supplier.id}
                    />
                    <div>
                      <span class="font-medium">{supplier.name}</span>
                      <div class="flex gap-1 mt-0.5">
                        <%= if supplier.supports_delivery do %>
                          <span class="badge badge-xs badge-ghost">Delivery</span>
                        <% end %>
                        <%= if supplier.supports_pricing do %>
                          <span class="badge badge-xs badge-ghost">Pricing</span>
                        <% end %>
                      </div>
                    </div>
                  </div>
                  <%= if MapSet.member?(@enabled_ids, supplier.id) do %>
                    <%= if @default_supplier_id == supplier.id do %>
                      <span class="badge badge-primary badge-sm">Default</span>
                    <% else %>
                      <button
                        phx-click="set_default"
                        phx-value-id={supplier.id}
                        class="btn btn-ghost btn-xs"
                      >
                        Set Default
                      </button>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Custom Suppliers --%>
        <div class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h3 class="card-title text-base">Custom Suppliers</h3>
              <button phx-click="show_add_custom" class="btn btn-ghost btn-sm">
                <.icon name="hero-plus" class="size-4" /> Add
              </button>
            </div>
            <p class="text-sm text-base-content/60">
              Add your local shops, farmers markets, or specialty stores.
            </p>

            <%= if @custom_suppliers == [] and not @adding_custom do %>
              <p class="text-sm text-base-content/40 mt-3 text-center py-4">
                No custom suppliers yet.
              </p>
            <% end %>

            <div class="space-y-2 mt-3">
              <%= for supplier <- @custom_suppliers do %>
                <div class="flex items-center justify-between py-2 border-b border-base-200 last:border-0">
                  <div>
                    <span class="font-medium">{supplier.name}</span>
                    <div class="flex gap-1 mt-0.5">
                      <%= if supplier.supplier_type do %>
                        <span class="badge badge-xs badge-ghost capitalize">
                          {format_type(supplier.supplier_type)}
                        </span>
                      <% end %>
                      <%= if supplier.address do %>
                        <span class="text-xs text-base-content/50">{supplier.address}</span>
                      <% end %>
                    </div>
                  </div>
                  <div class="flex items-center gap-1">
                    <%= if @default_supplier_id == supplier.id do %>
                      <span class="badge badge-primary badge-sm">Default</span>
                    <% else %>
                      <%= if MapSet.member?(@enabled_ids, supplier.id) do %>
                        <button
                          phx-click="set_default"
                          phx-value-id={supplier.id}
                          class="btn btn-ghost btn-xs"
                        >
                          Set Default
                        </button>
                      <% end %>
                    <% end %>
                    <button
                      phx-click="delete_custom"
                      phx-value-id={supplier.id}
                      data-confirm="Delete this supplier?"
                      class="btn btn-ghost btn-xs text-error"
                    >
                      <.icon name="hero-trash" class="size-3" />
                    </button>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Add Custom Form --%>
            <%= if @adding_custom do %>
              <div class="mt-4 p-4 bg-base-200 rounded-lg">
                <.simple_form
                  for={@custom_form}
                  phx-change="validate_custom"
                  phx-submit="save_custom"
                >
                  <.input field={@custom_form[:name]} type="text" label="Name" />
                  <.input
                    field={@custom_form[:supplier_type]}
                    type="select"
                    label="Type"
                    options={supplier_type_options()}
                  />
                  <.input field={@custom_form[:website_url]} type="text" label="Website (optional)" />
                  <.input field={@custom_form[:address]} type="text" label="Address (optional)" />
                  <.input
                    field={@custom_form[:deep_link_search_template]}
                    type="text"
                    label="Search URL Template (optional)"
                    placeholder="https://example.com/search?q={query}"
                  />
                  <.input field={@custom_form[:notes]} type="textarea" label="Notes (optional)" />
                  <:actions>
                    <.button phx-disable-with="Saving...">Add Supplier</.button>
                    <button type="button" phx-click="cancel_add_custom" class="btn btn-ghost btn-sm">
                      Cancel
                    </button>
                  </:actions>
                </.simple_form>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <.back navigate={~p"/households/#{@household.id}/settings"}>Back to settings</.back>
    </div>
    """
  end

  defp supplier_type_options do
    [
      {"Select type...", ""},
      {"Grocery Store", "grocery"},
      {"Butcher", "butcher"},
      {"Farmers Market", "farmers_market"},
      {"Specialty Store", "specialty"},
      {"Warehouse/Bulk", "warehouse"},
      {"Online", "online"},
      {"Other", "other"}
    ]
  end

  defp format_type(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp format_type(type) when is_binary(type), do: String.replace(type, "_", " ")
end
