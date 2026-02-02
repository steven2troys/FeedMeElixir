defmodule FeedMeWeb.PantryLive.ItemFormComponent do
  use FeedMeWeb, :live_component

  alias FeedMe.Pantry
  alias FeedMe.Pantry.Item

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
      </.header>

      <.simple_form
        for={@form}
        id="item-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" />

        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:quantity]} type="number" label="Quantity" step="any" min="0" />
          <.input field={@form[:unit]} type="text" label="Unit" placeholder="e.g., lbs, oz, pcs" />
        </div>

        <.input
          field={@form[:category_id]}
          type="select"
          label="Category"
          prompt="Select category..."
          options={Enum.map(@categories, &{&1.name, &1.id})}
        />

        <.input field={@form[:expiration_date]} type="date" label="Expiration Date" />

        <div class="divider">Auto-Restock Settings</div>

        <.input field={@form[:always_in_stock]} type="checkbox" label="Always keep in stock" />
        <.input
          field={@form[:restock_threshold]}
          type="number"
          label="Restock when quantity falls to"
          step="any"
          min="0"
        />

        <div class="divider">Additional Info</div>

        <.input field={@form[:barcode]} type="text" label="Barcode" />
        <.input field={@form[:notes]} type="textarea" label="Notes" />
        <.input field={@form[:is_standard]} type="checkbox" label="Standard item (appears in suggestions)" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Item</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{item: item} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Item.changeset(item, %{}))
     end)}
  end

  @impl true
  def handle_event("validate", %{"item" => item_params}, socket) do
    changeset =
      socket.assigns.item
      |> Item.changeset(item_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"item" => item_params}, socket) do
    save_item(socket, socket.assigns.action, item_params)
  end

  defp save_item(socket, :new, item_params) do
    params = Map.put(item_params, "household_id", socket.assigns.household.id)

    case Pantry.create_item(params) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Item created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_item(socket, :edit, item_params) do
    case Pantry.update_item(socket.assigns.item, item_params) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Item updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
