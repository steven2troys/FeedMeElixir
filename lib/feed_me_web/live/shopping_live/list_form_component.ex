defmodule FeedMeWeb.ShoppingLive.ListFormComponent do
  use FeedMeWeb, :live_component

  alias FeedMe.Shopping
  alias FeedMe.Shopping.List, as: ShoppingList

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
      </.header>

      <.simple_form
        for={@form}
        id="list-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="List Name" />
        <:actions>
          <.button phx-disable-with="Saving...">Create List</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{list: list} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
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
    params = Map.put(list_params, "household_id", socket.assigns.household.id)

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
