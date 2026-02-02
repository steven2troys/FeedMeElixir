defmodule FeedMeWeb.HouseholdLive.Members do
  use FeedMeWeb, :live_view

  alias FeedMe.Households
  alias FeedMe.Households.Invitation

  @impl true
  def mount(%{"id" => household_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Households.get_household_for_user(household_id, user) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Household not found or you don't have access")
         |> push_navigate(to: ~p"/households")}

      %{household: household, role: role} ->
        members = Households.list_members(household_id)
        invitations = Households.list_pending_invitations(household_id)

        {:ok,
         socket
         |> assign(:household, household)
         |> assign(:role, role)
         |> assign(:members, members)
         |> assign(:invitations, invitations)
         |> assign(:page_title, "#{household.name} - Members")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :invite, _params) do
    socket
    |> assign(:page_title, "Invite Member")
    |> assign(:invitation, %Invitation{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "#{socket.assigns.household.name} - Members")
    |> assign(:invitation, nil)
  end

  @impl true
  def handle_event("remove_member", %{"id" => membership_id}, socket) do
    if socket.assigns.role == :admin do
      Households.remove_member(membership_id)

      {:noreply,
       socket
       |> put_flash(:info, "Member removed")
       |> assign(:members, Households.list_members(socket.assigns.household.id))}
    else
      {:noreply, put_flash(socket, :error, "Only admins can remove members")}
    end
  end

  def handle_event("change_role", %{"id" => membership_id, "role" => role}, socket) do
    if socket.assigns.role == :admin do
      role_atom = String.to_existing_atom(role)
      Households.update_member_role(membership_id, role_atom)

      {:noreply,
       socket
       |> put_flash(:info, "Role updated")
       |> assign(:members, Households.list_members(socket.assigns.household.id))}
    else
      {:noreply, put_flash(socket, :error, "Only admins can change roles")}
    end
  end

  def handle_event("revoke_invitation", %{"id" => invitation_id}, socket) do
    if socket.assigns.role == :admin do
      Households.revoke_invitation(invitation_id)

      {:noreply,
       socket
       |> put_flash(:info, "Invitation revoked")
       |> assign(:invitations, Households.list_pending_invitations(socket.assigns.household.id))}
    else
      {:noreply, put_flash(socket, :error, "Only admins can revoke invitations")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        <%= @household.name %> - Members
        <:actions>
          <%= if @role == :admin do %>
            <.link patch={~p"/households/#{@household.id}/invite"}>
              <.button>Invite Member</.button>
            </.link>
          <% end %>
        </:actions>
      </.header>

      <div class="mt-8">
        <h3 class="text-lg font-semibold mb-4">Members (<%= length(@members) %>)</h3>
        <div class="space-y-3">
          <%= for %{user: member, role: member_role, membership_id: membership_id} <- @members do %>
            <div class="flex items-center justify-between p-4 bg-white dark:bg-zinc-800 rounded-lg border border-zinc-200 dark:border-zinc-700">
              <div class="flex items-center gap-3">
                <%= if member.avatar_url do %>
                  <img
                    src={member.avatar_url}
                    alt={member.name || member.email}
                    class="w-10 h-10 rounded-full"
                  />
                <% else %>
                  <div class="w-10 h-10 rounded-full bg-brand/10 flex items-center justify-center">
                    <span class="text-brand font-semibold">
                      <%= String.first(member.name || member.email) |> String.upcase() %>
                    </span>
                  </div>
                <% end %>
                <div>
                  <p class="font-medium"><%= member.name || member.email %></p>
                  <%= if member.name do %>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400"><%= member.email %></p>
                  <% end %>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <%= if @role == :admin && member.id != @current_scope.user.id do %>
                  <select
                    phx-change="change_role"
                    phx-value-id={membership_id}
                    name="role"
                    class="text-sm rounded-md border-zinc-300 dark:border-zinc-600 dark:bg-zinc-700"
                  >
                    <option value="admin" selected={member_role == :admin}>Admin</option>
                    <option value="member" selected={member_role == :member}>Member</option>
                  </select>
                  <button
                    phx-click="remove_member"
                    phx-value-id={membership_id}
                    data-confirm="Are you sure you want to remove this member?"
                    class="text-red-600 hover:text-red-700 p-1"
                  >
                    <.icon name="hero-trash" class="w-5 h-5" />
                  </button>
                <% else %>
                  <span class={[
                    "px-2 py-1 text-xs rounded-full",
                    member_role == :admin && "bg-brand/10 text-brand",
                    member_role == :member && "bg-zinc-100 dark:bg-zinc-700 text-zinc-600 dark:text-zinc-300"
                  ]}>
                    <%= member_role %>
                  </span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%= if @role == :admin && @invitations != [] do %>
        <div class="mt-8">
          <h3 class="text-lg font-semibold mb-4">Pending Invitations (<%= length(@invitations) %>)</h3>
          <div class="space-y-3">
            <%= for invitation <- @invitations do %>
              <div class="flex items-center justify-between p-4 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg border border-yellow-200 dark:border-yellow-700">
                <div>
                  <p class="font-medium"><%= invitation.email %></p>
                  <p class="text-sm text-zinc-500 dark:text-zinc-400">
                    Expires <%= Calendar.strftime(invitation.expires_at, "%B %d, %Y") %>
                  </p>
                </div>
                <div class="flex items-center gap-2">
                  <span class="px-2 py-1 text-xs rounded-full bg-yellow-100 dark:bg-yellow-800 text-yellow-700 dark:text-yellow-200">
                    Pending
                  </span>
                  <button
                    phx-click="revoke_invitation"
                    phx-value-id={invitation.id}
                    data-confirm="Are you sure you want to revoke this invitation?"
                    class="text-red-600 hover:text-red-700 p-1"
                  >
                    <.icon name="hero-x-mark" class="w-5 h-5" />
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <.back navigate={~p"/households/#{@household.id}"}>Back to household</.back>

      <.modal
        :if={@live_action == :invite}
        id="invite-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@household.id}/members")}
      >
        <.live_component
          module={FeedMeWeb.HouseholdLive.InviteComponent}
          id={:new}
          title="Invite Member"
          household={@household}
          current_user={@current_scope.user}
          patch={~p"/households/#{@household.id}/members"}
        />
      </.modal>
    </div>
    """
  end
end
