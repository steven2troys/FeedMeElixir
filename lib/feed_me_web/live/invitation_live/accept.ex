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
         |> assign(:household_name, "")
         |> assign(:page_title, "Invalid Invitation")}

      %Invitation{} = invitation ->
        cond do
          Invitation.accepted?(invitation) ->
            {:ok,
             socket
             |> assign(:invitation, invitation)
             |> assign(:error, :already_accepted)
             |> assign(:household_name, "")
             |> assign(:page_title, "Invitation Already Accepted")}

          Invitation.expired?(invitation) ->
            {:ok,
             socket
             |> assign(:invitation, invitation)
             |> assign(:error, :expired)
             |> assign(:household_name, "")
             |> assign(:page_title, "Invitation Expired")}

          invitation.type == :join_household and Households.member?(user, invitation.household_id) ->
            {:ok,
             socket
             |> assign(:invitation, invitation)
             |> assign(:error, :already_member)
             |> assign(:household_name, "")
             |> assign(:page_title, "Already a Member")}

          true ->
            {:ok,
             socket
             |> assign(:invitation, invitation)
             |> assign(:error, nil)
             |> assign(:household_name, "")
             |> assign(:page_title, "Accept Invitation")}
        end
    end
  end

  @impl true
  def handle_event("accept", params, socket) do
    user = socket.assigns.current_scope.user
    invitation = socket.assigns.invitation

    opts =
      if invitation.type == :new_household do
        [household_name: Map.get(params, "household_name", "")]
      else
        []
      end

    case Households.accept_invitation(invitation, user, opts) do
      {:ok, _membership} when invitation.type == :join_household ->
        {:noreply,
         socket
         |> put_flash(:info, "You've joined #{invitation.household.name}!")
         |> push_navigate(to: ~p"/households/#{invitation.household_id}")}

      {:ok, household} when invitation.type == :new_household ->
        {:noreply,
         socket
         |> put_flash(:info, "Your household \"#{household.name}\" has been created!")
         |> push_navigate(to: ~p"/households/#{household.id}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, reason)
         |> put_flash(:error, error_message(reason))}
    end
  end

  def handle_event("update_household_name", %{"household_name" => name}, socket) do
    {:noreply, assign(socket, :household_name, name)}
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
            <.link navigate={~p"/"}>
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
            <.link navigate={~p"/"}>
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
            <.link navigate={~p"/"}>
              <.button>Go to Households</.button>
            </.link>
          <% :already_member -> %>
            <div class="text-blue-500 mb-4">
              <.icon name="hero-user-group" class="w-16 h-16 mx-auto" />
            </div>
            <h2 class="text-xl font-semibold mb-2">Already a Member</h2>
            <p class="text-zinc-500 dark:text-zinc-400 mb-6">
              You're already a member of {@invitation.household.name}.
            </p>
            <.link navigate={~p"/households/#{@invitation.household_id}"}>
              <.button>Go to Household</.button>
            </.link>
          <% nil -> %>
            <div class="text-brand mb-4">
              <.icon name="hero-envelope" class="w-16 h-16 mx-auto" />
            </div>
            <h2 class="text-xl font-semibold mb-2">You're Invited!</h2>
            <%= if @invitation.type == :new_household do %>
              <p class="text-zinc-500 dark:text-zinc-400 mb-6">
                You've been invited to start your own household on FeedMe.
              </p>
              <form phx-submit="accept" phx-change="update_household_name" class="mb-4">
                <div class="text-left mb-4">
                  <label for="household_name" class="block text-sm font-semibold text-zinc-800 dark:text-zinc-200 mb-1">
                    Household Name
                  </label>
                  <input
                    type="text"
                    id="household_name"
                    name="household_name"
                    value={@household_name}
                    required
                    class="w-full rounded-lg border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-900 px-3 py-2 text-sm text-zinc-900 dark:text-zinc-100 focus:ring-2 focus:ring-brand"
                    placeholder="e.g. The Smith Family"
                  />
                </div>
                <div class="flex gap-3 justify-center">
                  <.button type="submit" variant="primary">Create Household</.button>
                  <.link navigate={~p"/"} class="btn btn-ghost">
                    Decline
                  </.link>
                </div>
              </form>
            <% else %>
              <p class="text-zinc-500 dark:text-zinc-400 mb-6">
                You've been invited to join <strong>{@invitation.household.name}</strong>.
              </p>
              <div class="flex gap-3 justify-center">
                <.button phx-click="accept" variant="primary">Accept Invitation</.button>
                <.link navigate={~p"/"} class="btn btn-ghost">
                  Decline
                </.link>
              </div>
            <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
