defmodule FeedMeWeb.ProfileLive.Edit do
  use FeedMeWeb, :live_view

  alias FeedMe.Profiles

  @impl true
  def mount(_params, _session, socket) do
    # household and role are set by HouseholdHooks
    user = socket.assigns.current_scope.user
    household = socket.assigns.household

    profile = Profiles.get_or_create_taste_profile(user.id, household.id)

    {:ok,
     socket
     |> assign(:active_tab, :profile)
     |> assign(:profile, profile)
     |> assign(:form, to_form(Profiles.change_taste_profile(profile)))
     |> assign(:page_title, "Taste Profile")}
  end

  @impl true
  def handle_event("validate", %{"taste_profile" => profile_params}, socket) do
    changeset =
      socket.assigns.profile
      |> Profiles.change_taste_profile(profile_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"taste_profile" => profile_params}, socket) do
    case Profiles.update_taste_profile(socket.assigns.profile, profile_params) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> put_flash(:info, "Taste profile updated successfully")
         |> assign(:profile, profile)
         |> assign(:form, to_form(Profiles.change_taste_profile(profile)))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("add_item", %{"field" => field, "value" => value}, socket) do
    field_atom = String.to_existing_atom(field)
    current_values = Map.get(socket.assigns.profile, field_atom) || []

    if value != "" and value not in current_values do
      new_values = current_values ++ [value]

      case Profiles.update_taste_profile(socket.assigns.profile, %{field_atom => new_values}) do
        {:ok, profile} ->
          {:noreply,
           socket
           |> assign(:profile, profile)
           |> assign(:form, to_form(Profiles.change_taste_profile(profile)))}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_item", %{"field" => field, "value" => value}, socket) do
    field_atom = String.to_existing_atom(field)
    current_values = Map.get(socket.assigns.profile, field_atom) || []
    new_values = List.delete(current_values, value)

    case Profiles.update_taste_profile(socket.assigns.profile, %{field_atom => new_values}) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(:profile, profile)
         |> assign(:form, to_form(Profiles.change_taste_profile(profile)))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <.header>
        Taste Profile
        <:subtitle>
          Manage your dietary preferences for {@household.name}
        </:subtitle>
      </.header>

      <div class="mt-8 space-y-8">
        <.tag_section
          title="Dietary Restrictions"
          description="e.g., Vegetarian, Vegan, Gluten-Free, Keto"
          field="dietary_restrictions"
          items={@profile.dietary_restrictions}
        />

        <.tag_section
          title="Allergies"
          description="e.g., Peanuts, Tree Nuts, Dairy, Shellfish"
          field="allergies"
          items={@profile.allergies}
        />

        <.tag_section
          title="Dislikes"
          description="Foods you prefer to avoid"
          field="dislikes"
          items={@profile.dislikes}
        />

        <.tag_section
          title="Favorites"
          description="Your favorite foods and ingredients"
          field="favorites"
          items={@profile.favorites}
        />

        <.simple_form for={@form} phx-change="validate" phx-submit="save">
          <.input field={@form[:notes]} type="textarea" label="Additional Notes" />
          <:actions>
            <.button phx-disable-with="Saving...">Save Notes</.button>
          </:actions>
        </.simple_form>
      </div>

      <.back navigate={~p"/households/#{@household.id}"}>Back to household</.back>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :field, :string, required: true
  attr :items, :list, required: true

  defp tag_section(assigns) do
    ~H"""
    <div class="space-y-3">
      <div>
        <h3 class="font-semibold">{@title}</h3>
        <p class="text-sm text-base-content/70">{@description}</p>
      </div>

      <div class="flex flex-wrap gap-2">
        <%= for item <- @items do %>
          <span class="badge badge-lg gap-1">
            {item}
            <button
              type="button"
              phx-click="remove_item"
              phx-value-field={@field}
              phx-value-value={item}
              class="cursor-pointer"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </span>
        <% end %>
      </div>

      <form phx-submit="add_item" class="flex gap-2">
        <input type="hidden" name="field" value={@field} />
        <input
          type="text"
          name="value"
          placeholder={"Add #{String.downcase(@title)}..."}
          class="input input-bordered flex-1"
        />
        <button type="submit" class="btn btn-primary">Add</button>
      </form>
    </div>
    """
  end
end
