defmodule FeedMeWeb.HouseholdLive.InviteComponent do
  use FeedMeWeb, :live_component

  alias FeedMe.Accounts.UserNotifier
  alias FeedMe.Households
  alias FeedMe.Households.Invitation

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          <%= if @invitation_type == "new_household" do %>
            Send an invitation to start their own household
          <% else %>
            Send an invitation to join {@household.name}
          <% end %>
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
          field={@form[:type]}
          type="select"
          label="Invitation Type"
          options={[{"Join my household", "join_household"}, {"Start their own household", "new_household"}]}
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
     |> assign_new(:invitation_type, fn -> "join_household" end)
     |> assign_new(:form, fn ->
       to_form(
         Invitation.changeset(%Invitation{household_id: assigns.household.id}, %{type: :join_household})
       )
     end)}
  end

  @impl true
  def handle_event("validate", %{"invitation" => invitation_params}, socket) do
    changeset =
      %Invitation{household_id: socket.assigns.household.id}
      |> Invitation.changeset(invitation_params)
      |> Map.put(:action, :validate)

    invitation_type = Map.get(invitation_params, "type", "join_household")

    {:noreply, assign(socket, form: to_form(changeset), invitation_type: invitation_type)}
  end

  def handle_event("save", %{"invitation" => invitation_params}, socket) do
    params =
      invitation_params
      |> Map.put("household_id", socket.assigns.household.id)

    case Households.create_invitation(params, socket.assigns.current_user) do
      {:ok, invitation} ->
        invitation_url = url(socket, ~p"/invitations/#{invitation.token}")
        inviter_name = socket.assigns.current_user.name || socket.assigns.current_user.email

        if invitation.type == :new_household do
          UserNotifier.deliver_new_household_invitation_email(
            invitation.email,
            invitation_url,
            inviter_name
          )
        else
          UserNotifier.deliver_invitation_email(
            invitation.email,
            invitation_url,
            socket.assigns.household.name,
            inviter_name
          )
        end

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
