defmodule FeedMeWeb.InvitationLive.Accept do
  use FeedMeWeb, :live_view

  alias FeedMe.Households
  alias FeedMe.Households.Invitation

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Households.get_invitation_by_token(token) do
      nil ->
        {:ok,
         socket
         |> assign(:invitation, nil)
         |> assign(:error, :not_found)
         |> assign(:page_title, "Invalid Invitation")}

      %Invitation{} = invitation ->
        cond do
          Invitation.accepted?(invitation) ->
            {:ok,
             socket
             |> assign(:invitation, invitation)
             |> assign(:error, :already_accepted)
             |> assign(:page_title, "Invitation Already Accepted")}

          Invitation.expired?(invitation) ->
            {:ok,
             socket
             |> assign(:invitation, invitation)
             |> assign(:error, :expired)
             |> assign(:page_title, "Invitation Expired")}

          Households.member?(user, invitation.household_id) ->
            {:ok,
             socket
             |> assign(:invitation, invitation)
             |> assign(:error, :already_member)
             |> assign(:page_title, "Already a Member")}

          true ->
            {:ok,
             socket
             |> assign(:invitation, invitation)
             |> assign(:error, nil)
             |> assign(:page_title, "Accept Invitation")}
        end
    end
  end

  @impl true
  def handle_event("accept", _params, socket) do
    user = socket.assigns.current_scope.user
    invitation = socket.assigns.invitation

    case Households.accept_invitation(invitation, user) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> put_flash(:info, "You've joined #{invitation.household.name}!")
         |> push_navigate(to: ~p"/households/#{invitation.household_id}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, reason)
         |> put_flash(:error, error_message(reason))}
    end
  end

  defp error_message(:expired), do: "This invitation has expired."
  defp error_message(:already_accepted), do: "This invitation has already been used."
  defp error_message(:already_member), do: "You're already a member of this household."
  defp error_message(_), do: "Something went wrong. Please try again."

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md mt-20">
      <div class="bg-white dark:bg-zinc-800 rounded-lg border border-zinc-200 dark:border-zinc-700 p-8 text-center">
        <%= case @error do %>
          <% :not_found -> %>
            <div class="text-red-500 mb-4">
              <.icon name="hero-x-circle" class="w-16 h-16 mx-auto" />
            </div>
            <h2 class="text-xl font-semibold mb-2">Invalid Invitation</h2>
            <p class="text-zinc-500 dark:text-zinc-400 mb-6">
              This invitation link is invalid or has been revoked.
            </p>
            <.link navigate={~p"/households"}>
              <.button>Go to Households</.button>
            </.link>
          <% :expired -> %>
            <div class="text-yellow-500 mb-4">
              <.icon name="hero-clock" class="w-16 h-16 mx-auto" />
            </div>
            <h2 class="text-xl font-semibold mb-2">Invitation Expired</h2>
            <p class="text-zinc-500 dark:text-zinc-400 mb-6">
              This invitation has expired. Please ask the household admin to send a new one.
            </p>
            <.link navigate={~p"/households"}>
              <.button>Go to Households</.button>
            </.link>
          <% :already_accepted -> %>
            <div class="text-green-500 mb-4">
              <.icon name="hero-check-circle" class="w-16 h-16 mx-auto" />
            </div>
            <h2 class="text-xl font-semibold mb-2">Already Accepted</h2>
            <p class="text-zinc-500 dark:text-zinc-400 mb-6">
              This invitation has already been used.
            </p>
            <.link navigate={~p"/households"}>
              <.button>Go to Households</.button>
            </.link>
          <% :already_member -> %>
            <div class="text-blue-500 mb-4">
              <.icon name="hero-user-group" class="w-16 h-16 mx-auto" />
            </div>
            <h2 class="text-xl font-semibold mb-2">Already a Member</h2>
            <p class="text-zinc-500 dark:text-zinc-400 mb-6">
              You're already a member of <%= @invitation.household.name %>.
            </p>
            <.link navigate={~p"/households/#{@invitation.household_id}"}>
              <.button>Go to Household</.button>
            </.link>
          <% nil -> %>
            <div class="text-brand mb-4">
              <.icon name="hero-envelope" class="w-16 h-16 mx-auto" />
            </div>
            <h2 class="text-xl font-semibold mb-2">You're Invited!</h2>
            <p class="text-zinc-500 dark:text-zinc-400 mb-6">
              You've been invited to join <strong><%= @invitation.household.name %></strong>
              as a <strong><%= @invitation.role %></strong>.
            </p>
            <div class="flex gap-3 justify-center">
              <.button phx-click="accept" variant="primary">Accept Invitation</.button>
              <.link navigate={~p"/households"} class="btn btn-ghost">
                Decline
              </.link>
            </div>
        <% end %>
      </div>
    </div>
    """
  end
end
