defmodule FeedMeWeb.HouseholdLive.InviteComponent do
  use FeedMeWeb, :live_component

  alias FeedMe.Households
  alias FeedMe.Households.Invitation

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          Send an invitation to join {@household.name}
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="invitation-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:email]} type="email" label="Email Address" />
        <.input
          field={@form[:role]}
          type="select"
          label="Role"
          options={[{"Member", "member"}, {"Admin", "admin"}]}
        />
        <:actions>
          <.button phx-disable-with="Sending...">Send Invitation</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(
         Invitation.changeset(%Invitation{household_id: assigns.household.id}, %{role: :member})
       )
     end)}
  end

  @impl true
  def handle_event("validate", %{"invitation" => invitation_params}, socket) do
    changeset =
      %Invitation{household_id: socket.assigns.household.id}
      |> Invitation.changeset(invitation_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"invitation" => invitation_params}, socket) do
    params =
      invitation_params
      |> Map.put("household_id", socket.assigns.household.id)

    case Households.create_invitation(params, socket.assigns.current_user) do
      {:ok, invitation} ->
        # In a real app, you'd send an email here
        send(self(), {:invitation_created, invitation})

        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{invitation.email}")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
