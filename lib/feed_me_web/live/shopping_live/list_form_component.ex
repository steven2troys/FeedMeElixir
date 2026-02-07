defmodule FeedMeWeb.ShoppingLive.ListFormComponent do
  use FeedMeWeb, :live_component

  alias FeedMe.Pantry
  alias FeedMe.Shopping
  alias FeedMe.Shopping.List, as: ShoppingList

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.simple_form
        for={@form}
        id="list-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="List Name" />
        <div class="form-control">
          <label class="label"><span class="label-text">Auto-add checked items to</span></label>
          <select
            name="list[auto_add_to_location_id]"
            class="select select-bordered"
          >
            <option value="">None</option>
            <%= for loc <- @storage_locations, not loc.is_default do %>
              <option value={loc.id}>{loc.name}</option>
            <% end %>
          </select>
          <label class="label">
            <span class="label-text-alt">
              When set, checked items will update inventory in the selected location.
            </span>
          </label>
        </div>
        <:actions>
          <.button phx-disable-with="Saving...">Create List</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{list: list} = assigns, socket) do
    storage_locations = Pantry.list_storage_locations(assigns.household.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:storage_locations, storage_locations)
     |> assign_new(:form, fn ->
       to_form(ShoppingList.changeset(list, %{}))
     end)}
  end

  @impl true
  def handle_event("validate", %{"list" => list_params}, socket) do
    changeset =
      socket.assigns.list
      |> ShoppingList.changeset(list_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"list" => list_params}, socket) do
    location_id = list_params["auto_add_to_location_id"]

    params =
      list_params
      |> Map.put("household_id", socket.assigns.household.id)
      |> Map.put("created_by_id", socket.assigns.current_scope.user.id)
      |> Map.put("add_to_pantry", location_id != "" && location_id != nil)

    case Shopping.create_list(params) do
      {:ok, list} ->
        {:noreply,
         socket
         |> put_flash(:info, "List created successfully")
         |> push_navigate(to: ~p"/households/#{socket.assigns.household.id}/shopping/#{list.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
