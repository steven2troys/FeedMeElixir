defmodule FeedMeWeb.HouseholdLive.FormComponent do
  use FeedMeWeb, :live_component

  alias FeedMe.Households
  alias FeedMe.Households.Household

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.simple_form
        for={@form}
        id="household-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Household Name" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Household</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{household: household} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Household.changeset(household, %{}))
     end)}
  end

  @impl true
  def handle_event("validate", %{"household" => household_params}, socket) do
    changeset =
      socket.assigns.household
      |> Household.changeset(household_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"household" => household_params}, socket) do
    save_household(socket, socket.assigns.action, household_params)
  end

  defp save_household(socket, :new, household_params) do
    case Households.create_household(household_params, socket.assigns.current_user) do
      {:ok, household} ->
        {:noreply,
         socket
         |> put_flash(:info, "Household created successfully")
         |> push_navigate(to: ~p"/households/#{household.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_household(socket, :edit, household_params) do
    case Households.update_household(socket.assigns.household, household_params) do
      {:ok, _household} ->
        {:noreply,
         socket
         |> put_flash(:info, "Household updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
