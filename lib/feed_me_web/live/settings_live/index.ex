defmodule FeedMeWeb.SettingsLive.Index do
  use FeedMeWeb, :live_view

  alias FeedMe.Households
  alias FeedMe.Households.Household

  @automation_tiers [
    {"Off", "off", "AI won't proactively suggest or take actions"},
    {"Recommend", "recommend", "AI prepares suggestions for your review"},
    {"Cart Fill", "cart_fill", "AI can fill vendor carts (coming soon)"},
    {"Auto Purchase", "auto_purchase", "AI can purchase within budget (coming soon)"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    household = socket.assigns.household
    role = socket.assigns.role

    changeset = Household.changeset(household, %{})

    {:ok,
     socket
     |> assign(:active_tab, :settings)
     |> assign(:page_title, "Settings")
     |> assign(:name_form, to_form(changeset))
     |> assign(:editing_name, false)
     |> assign(:role, role)}
  end

  @impl true
  def handle_event("edit_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, true)}
  end

  def handle_event("cancel_edit_name", _params, socket) do
    changeset = Household.changeset(socket.assigns.household, %{})
    {:noreply, socket |> assign(:editing_name, false) |> assign(:name_form, to_form(changeset))}
  end

  def handle_event("validate_name", %{"household" => params}, socket) do
    changeset =
      socket.assigns.household
      |> Household.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :name_form, to_form(changeset))}
  end

  def handle_event("save_name", %{"household" => params}, socket) do
    case Households.update_household(socket.assigns.household, params) do
      {:ok, household} ->
        changeset = Household.changeset(household, %{})

        {:noreply,
         socket
         |> assign(:household, household)
         |> assign(:name_form, to_form(changeset))
         |> assign(:editing_name, false)
         |> put_flash(:info, "Household name updated")}

      {:error, changeset} ->
        {:noreply, assign(socket, :name_form, to_form(changeset))}
    end
  end

  def handle_event("save_automation_tier", %{"automation_tier" => tier}, socket) do
    case Households.update_household(socket.assigns.household, %{automation_tier: tier}) do
      {:ok, household} ->
        {:noreply,
         socket
         |> assign(:household, household)
         |> put_flash(:info, "Automation tier updated")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update automation tier")}
    end
  end

  def handle_event("save_schedule", params, socket) do
    attrs = %{
      weekly_suggestion_enabled: params["weekly_suggestion_enabled"] == "true",
      weekly_suggestion_day: String.to_integer(params["weekly_suggestion_day"] || "7"),
      daily_pantry_check_enabled: params["daily_pantry_check_enabled"] == "true"
    }

    case Households.update_household(socket.assigns.household, attrs) do
      {:ok, household} ->
        {:noreply,
         socket
         |> assign(:household, household)
         |> put_flash(:info, "Schedule settings updated")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update schedule")}
    end
  end

  def handle_event("save_timezone", %{"timezone" => timezone}, socket) do
    case Households.update_household(socket.assigns.household, %{timezone: timezone}) do
      {:ok, household} ->
        {:noreply,
         socket
         |> assign(:household, household)
         |> put_flash(:info, "Timezone updated to #{timezone}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update timezone")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        Settings
        <:subtitle>Manage your household and account settings</:subtitle>
      </.header>

      <div class="mt-6 space-y-6">
        <%!-- General Section --%>
        <div class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="card-title">General</h3>

            <%!-- Household Name --%>
            <div class="mt-2">
              <label class="text-sm font-medium text-base-content/70">Household Name</label>
              <%= if @editing_name do %>
                <.simple_form
                  for={@name_form}
                  phx-change="validate_name"
                  phx-submit="save_name"
                  class="mt-1"
                >
                  <.input field={@name_form[:name]} type="text" />
                  <:actions>
                    <.button phx-disable-with="Saving...">Save</.button>
                    <button type="button" phx-click="cancel_edit_name" class="btn btn-ghost btn-sm">
                      Cancel
                    </button>
                  </:actions>
                </.simple_form>
              <% else %>
                <div class="flex items-center justify-between mt-1">
                  <span class="text-lg font-semibold">{@household.name}</span>
                  <%= if @role == :admin do %>
                    <button phx-click="edit_name" class="btn btn-ghost btn-sm">
                      <.icon name="hero-pencil" class="size-4" /> Edit
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Timezone --%>
            <div class="mt-4">
              <label class="text-sm font-medium text-base-content/70">Timezone</label>
              <p class="text-xs text-base-content/50 mt-0.5">
                Used for expiration date calculations when adding pantry items.
              </p>
              <%= if @role == :admin do %>
                <form phx-submit="save_timezone" class="mt-2">
                  <div class="flex gap-2">
                    <select name="timezone" class="select select-bordered select-sm flex-1">
                      <optgroup label="Common US Timezones">
                        <%= for tz <- common_us_timezones() do %>
                          <option value={tz} selected={@household.timezone == tz}>{tz}</option>
                        <% end %>
                      </optgroup>
                      <%= for {region, zones} <- grouped_timezones() do %>
                        <optgroup label={region}>
                          <%= for tz <- zones do %>
                            <option value={tz} selected={@household.timezone == tz}>{tz}</option>
                          <% end %>
                        </optgroup>
                      <% end %>
                    </select>
                    <button type="submit" class="btn btn-primary btn-sm">Save</button>
                  </div>
                </form>
              <% else %>
                <p class="mt-1 text-base-content">{@household.timezone}</p>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- AI Settings --%>
        <.link
          navigate={~p"/households/#{@household.id}/settings/api-key"}
          class="card bg-base-100 border border-base-200 hover:border-primary hover:shadow-md transition-all"
        >
          <div class="card-body flex-row items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-cpu-chip" class="size-6 text-primary" />
              <div>
                <h3 class="font-semibold">AI Settings</h3>
                <p class="text-sm text-base-content/60">API keys and model selection</p>
              </div>
            </div>
            <.icon name="hero-chevron-right" class="size-5 text-base-content/40" />
          </div>
        </.link>

        <%!-- AI Automation (Admin only) --%>
        <%= if @role == :admin do %>
          <div class="card bg-base-100 border border-base-200">
            <div class="card-body">
              <div class="flex items-center gap-3">
                <.icon name="hero-bolt" class="size-6 text-primary" />
                <div>
                  <h3 class="font-semibold">AI Automation</h3>
                  <p class="text-sm text-base-content/60">
                    Control how proactively AI assists with procurement
                  </p>
                </div>
              </div>
              <form phx-submit="save_automation_tier" class="mt-3">
                <div class="space-y-2">
                  <%= for {label, value, desc} <- automation_tiers() do %>
                    <label class={[
                      "flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors",
                      to_string(@household.automation_tier) == value && "border-primary bg-primary/5",
                      to_string(@household.automation_tier) != value &&
                        "border-base-200 hover:border-base-300"
                    ]}>
                      <input
                        type="radio"
                        name="automation_tier"
                        value={value}
                        checked={to_string(@household.automation_tier) == value}
                        class="radio radio-sm radio-primary mt-0.5"
                      />
                      <div>
                        <span class="font-medium text-sm">{label}</span>
                        <p class="text-xs text-base-content/60">{desc}</p>
                      </div>
                    </label>
                  <% end %>
                </div>
                <button type="submit" class="btn btn-primary btn-sm mt-3">Save</button>
              </form>

              <%!-- Schedule Settings (only show when not :off) --%>
              <%= if @household.automation_tier != :off do %>
                <div class="divider"></div>
                <h4 class="font-medium text-sm">Schedule</h4>
                <form phx-submit="save_schedule" class="mt-2 space-y-3">
                  <label class="flex items-center gap-3">
                    <input
                      type="checkbox"
                      name="weekly_suggestion_enabled"
                      value="true"
                      checked={@household.weekly_suggestion_enabled}
                      class="checkbox checkbox-sm checkbox-primary"
                    />
                    <span class="text-sm">Weekly meal plan suggestions</span>
                  </label>
                  <div class="ml-8">
                    <select
                      name="weekly_suggestion_day"
                      class="select select-bordered select-xs"
                    >
                      <%= for {name, val} <- day_options() do %>
                        <option value={val} selected={@household.weekly_suggestion_day == val}>
                          {name}
                        </option>
                      <% end %>
                    </select>
                  </div>
                  <label class="flex items-center gap-3">
                    <input
                      type="checkbox"
                      name="daily_pantry_check_enabled"
                      value="true"
                      checked={@household.daily_pantry_check_enabled}
                      class="checkbox checkbox-sm checkbox-primary"
                    />
                    <span class="text-sm">Daily pantry restock & expiry check</span>
                  </label>
                  <button type="submit" class="btn btn-primary btn-sm">Save Schedule</button>
                </form>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- Suppliers --%>
        <.link
          navigate={~p"/households/#{@household.id}/settings/suppliers"}
          class="card bg-base-100 border border-base-200 hover:border-primary hover:shadow-md transition-all"
        >
          <div class="card-body flex-row items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-building-storefront" class="size-6 text-primary" />
              <div>
                <h3 class="font-semibold">Suppliers</h3>
                <p class="text-sm text-base-content/60">Manage grocery suppliers</p>
              </div>
            </div>
            <.icon name="hero-chevron-right" class="size-5 text-base-content/40" />
          </div>
        </.link>

        <%!-- My Households --%>
        <.link
          navigate={~p"/households/#{@household.id}/settings/households"}
          class="card bg-base-100 border border-base-200 hover:border-primary hover:shadow-md transition-all"
        >
          <div class="card-body flex-row items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-home-modern" class="size-6 text-primary" />
              <div>
                <h3 class="font-semibold">My Households</h3>
                <p class="text-sm text-base-content/60">Switch or manage households</p>
              </div>
            </div>
            <.icon name="hero-chevron-right" class="size-5 text-base-content/40" />
          </div>
        </.link>

        <%!-- Account Settings --%>
        <.link
          href={~p"/users/settings"}
          class="card bg-base-100 border border-base-200 hover:border-primary hover:shadow-md transition-all"
        >
          <div class="card-body flex-row items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-user-circle" class="size-6 text-primary" />
              <div>
                <h3 class="font-semibold">Account</h3>
                <p class="text-sm text-base-content/60">Email and password settings</p>
              </div>
            </div>
            <.icon name="hero-chevron-right" class="size-5 text-base-content/40" />
          </div>
        </.link>
      </div>
    </div>
    """
  end

  defp common_us_timezones do
    [
      "America/New_York",
      "America/Chicago",
      "America/Denver",
      "America/Los_Angeles",
      "America/Anchorage",
      "Pacific/Honolulu"
    ]
  end

  defp grouped_timezones do
    common = MapSet.new(common_us_timezones())

    all_timezones()
    |> Enum.reject(&MapSet.member?(common, &1))
    |> Enum.group_by(fn tz -> tz |> String.split("/") |> hd() end)
    |> Enum.sort_by(fn {region, _} -> region end)
  end

  defp automation_tiers, do: @automation_tiers

  defp day_options do
    [
      {"Monday", 1},
      {"Tuesday", 2},
      {"Wednesday", 3},
      {"Thursday", 4},
      {"Friday", 5},
      {"Saturday", 6},
      {"Sunday", 7}
    ]
  end

  defp all_timezones do
    [
      "Africa/Cairo",
      "Africa/Casablanca",
      "Africa/Johannesburg",
      "Africa/Lagos",
      "Africa/Nairobi",
      "America/Anchorage",
      "America/Argentina/Buenos_Aires",
      "America/Bogota",
      "America/Caracas",
      "America/Chicago",
      "America/Denver",
      "America/Edmonton",
      "America/Halifax",
      "America/Lima",
      "America/Los_Angeles",
      "America/Mexico_City",
      "America/New_York",
      "America/Phoenix",
      "America/Santiago",
      "America/Sao_Paulo",
      "America/Toronto",
      "America/Vancouver",
      "Asia/Bangkok",
      "Asia/Dubai",
      "Asia/Ho_Chi_Minh",
      "Asia/Hong_Kong",
      "Asia/Jakarta",
      "Asia/Jerusalem",
      "Asia/Kolkata",
      "Asia/Manila",
      "Asia/Seoul",
      "Asia/Shanghai",
      "Asia/Singapore",
      "Asia/Taipei",
      "Asia/Tokyo",
      "Australia/Adelaide",
      "Australia/Brisbane",
      "Australia/Darwin",
      "Australia/Melbourne",
      "Australia/Perth",
      "Australia/Sydney",
      "Europe/Amsterdam",
      "Europe/Athens",
      "Europe/Berlin",
      "Europe/Brussels",
      "Europe/Dublin",
      "Europe/Helsinki",
      "Europe/Istanbul",
      "Europe/Lisbon",
      "Europe/London",
      "Europe/Madrid",
      "Europe/Moscow",
      "Europe/Paris",
      "Europe/Rome",
      "Europe/Stockholm",
      "Europe/Vienna",
      "Europe/Warsaw",
      "Europe/Zurich",
      "Pacific/Auckland",
      "Pacific/Fiji",
      "Pacific/Guam",
      "Pacific/Honolulu"
    ]
  end
end
