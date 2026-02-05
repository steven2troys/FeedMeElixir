defmodule FeedMeWeb.HouseholdLive.Members do
  use FeedMeWeb, :live_view

  alias FeedMe.Accounts
  alias FeedMe.Households
  alias FeedMe.Households.Invitation
  alias FeedMe.Profiles

  @impl true
  def mount(_params, _session, socket) do
    # household and role are set by HouseholdHooks
    household = socket.assigns.household

    members = load_members_with_profiles(household.id)
    invitations = Households.list_pending_invitations(household.id)

    {:ok,
     socket
     |> assign(:active_tab, :members)
     |> assign(:members, members)
     |> assign(:invitations, invitations)
     |> assign(:editing_member, nil)
     |> assign(:page_title, "Members")}
  end

  defp load_members_with_profiles(household_id) do
    members = Households.list_members(household_id)

    Enum.map(members, fn member ->
      profile = Profiles.get_taste_profile(member.user.id, household_id)
      Map.put(member, :taste_profile, profile)
    end)
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :invite, _params) do
    socket
    |> assign(:page_title, "Invite Member")
    |> assign(:invitation, %Invitation{})
    |> assign(:editing_member, nil)
  end

  defp apply_action(socket, :edit_member, %{"member_id" => member_id}) do
    current_user = socket.assigns.current_scope.user
    role = socket.assigns.role
    household = socket.assigns.household

    member = Enum.find(socket.assigns.members, fn m -> m.user.id == member_id end)

    if member && (role == :admin || member.user.id == current_user.id) do
      profile = Profiles.get_or_create_taste_profile(member.user.id, household.id)

      socket
      |> assign(:page_title, "Edit Member Profile")
      |> assign(:editing_member, member)
      |> assign(:editing_profile, profile)
      |> assign(:profile_form, to_form(Profiles.change_taste_profile(profile)))
      |> assign(:user_form, to_form(Accounts.User.profile_changeset(member.user, %{})))
    else
      socket
      |> put_flash(:error, "You don't have permission to edit this profile")
      |> push_patch(to: ~p"/households/#{household.id}/members")
    end
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Members")
    |> assign(:invitation, nil)
    |> assign(:editing_member, nil)
  end

  @impl true
  def handle_event("edit_member", %{"id" => member_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/households/#{socket.assigns.household.id}/members/#{member_id}/edit")}
  end

  def handle_event("save_profile", %{"taste_profile" => profile_params}, socket) do
    case Profiles.update_taste_profile(socket.assigns.editing_profile, profile_params) do
      {:ok, _profile} ->
        {:noreply,
         socket
         |> put_flash(:info, "Taste profile updated")
         |> push_patch(to: ~p"/households/#{socket.assigns.household.id}/members")}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset))}
    end
  end

  def handle_event("save_user", %{"user" => user_params}, socket) do
    case Accounts.update_user_profile(socket.assigns.editing_member.user, user_params) do
      {:ok, _user} ->
        members = load_members_with_profiles(socket.assigns.household.id)

        {:noreply,
         socket
         |> put_flash(:info, "Profile updated")
         |> assign(:members, members)
         |> push_patch(to: ~p"/households/#{socket.assigns.household.id}/members")}

      {:error, changeset} ->
        {:noreply, assign(socket, :user_form, to_form(changeset))}
    end
  end

  def handle_event("add_item", %{"field" => field, "value" => value}, socket) do
    field_atom = String.to_existing_atom(field)
    profile = socket.assigns.editing_profile
    current_values = Map.get(profile, field_atom) || []

    if value != "" and value not in current_values do
      new_values = current_values ++ [value]

      case Profiles.update_taste_profile(profile, %{field_atom => new_values}) do
        {:ok, updated_profile} ->
          {:noreply,
           socket
           |> assign(:editing_profile, updated_profile)
           |> assign(:profile_form, to_form(Profiles.change_taste_profile(updated_profile)))}

        {:error, changeset} ->
          {:noreply, assign(socket, :profile_form, to_form(changeset))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_item", %{"field" => field, "value" => value}, socket) do
    field_atom = String.to_existing_atom(field)
    profile = socket.assigns.editing_profile
    current_values = Map.get(profile, field_atom) || []
    new_values = List.delete(current_values, value)

    case Profiles.update_taste_profile(profile, %{field_atom => new_values}) do
      {:ok, updated_profile} ->
        {:noreply,
         socket
         |> assign(:editing_profile, updated_profile)
         |> assign(:profile_form, to_form(Profiles.change_taste_profile(updated_profile)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset))}
    end
  end

  def handle_event("remove_member", %{"id" => membership_id}, socket) do
    if socket.assigns.role == :admin do
      Households.remove_member(membership_id)

      {:noreply,
       socket
       |> put_flash(:info, "Member removed")
       |> assign(:members, load_members_with_profiles(socket.assigns.household.id))}
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
       |> assign(:members, load_members_with_profiles(socket.assigns.household.id))}
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
        Members
        <:subtitle>Manage household members and their taste profiles</:subtitle>
        <:actions>
          <%= if @role == :admin do %>
            <.link patch={~p"/households/#{@household.id}/invite"}>
              <.button>Invite Member</.button>
            </.link>
          <% end %>
        </:actions>
      </.header>

      <div class="mt-8 space-y-4">
        <%= for member <- @members do %>
          <.member_card
            member={member}
            current_user={@current_scope.user}
            role={@role}
            household={@household}
          />
        <% end %>
      </div>

      <%= if @role == :admin && @invitations != [] do %>
        <div class="mt-8">
          <h3 class="text-lg font-semibold mb-4">Pending Invitations</h3>
          <div class="space-y-3">
            <%= for invitation <- @invitations do %>
              <div class="flex items-center justify-between p-4 bg-warning/10 rounded-lg border border-warning/30">
                <div>
                  <p class="font-medium"><%= invitation.email %></p>
                  <p class="text-sm text-base-content/60">
                    Expires <%= Calendar.strftime(invitation.expires_at, "%B %d, %Y") %>
                  </p>
                </div>
                <div class="flex items-center gap-2">
                  <span class="badge badge-warning">Pending</span>
                  <button
                    phx-click="revoke_invitation"
                    phx-value-id={invitation.id}
                    data-confirm="Are you sure you want to revoke this invitation?"
                    class="btn btn-ghost btn-sm text-error"
                  >
                    <.icon name="hero-x-mark" class="w-5 h-5" />
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

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

      <.modal
        :if={@live_action == :edit_member && @editing_member}
        id="edit-member-modal"
        show
        on_cancel={JS.patch(~p"/households/#{@household.id}/members")}
      >
        <.header>
          Edit Profile
          <:subtitle><%= @editing_member.user.name || @editing_member.user.email %></:subtitle>
        </.header>

        <div class="mt-6 space-y-6">
          <!-- User Info Section -->
          <div class="space-y-4">
            <h3 class="font-semibold">Basic Info</h3>
            <.simple_form for={@user_form} phx-submit="save_user">
              <.input field={@user_form[:name]} type="text" label="Display Name" />
              <div class="text-sm text-base-content/60">
                Email: <%= @editing_member.user.email %>
              </div>
              <:actions>
                <.button phx-disable-with="Saving...">Save Name</.button>
              </:actions>
            </.simple_form>
          </div>

          <div class="divider"></div>

          <!-- Taste Profile Section -->
          <div class="space-y-6">
            <h3 class="font-semibold">Taste Profile</h3>

            <.tag_section
              title="Dietary Restrictions"
              description="e.g., Vegetarian, Vegan, Gluten-Free"
              field="dietary_restrictions"
              items={@editing_profile.dietary_restrictions || []}
            />

            <.tag_section
              title="Allergies"
              description="e.g., Peanuts, Dairy, Shellfish"
              field="allergies"
              items={@editing_profile.allergies || []}
            />

            <.tag_section
              title="Dislikes"
              description="Foods to avoid"
              field="dislikes"
              items={@editing_profile.dislikes || []}
            />

            <.tag_section
              title="Favorites"
              description="Favorite foods"
              field="favorites"
              items={@editing_profile.favorites || []}
            />

            <.simple_form for={@profile_form} phx-submit="save_profile">
              <.input field={@profile_form[:notes]} type="textarea" label="Notes" />
              <:actions>
                <.button phx-disable-with="Saving...">Save Notes</.button>
              </:actions>
            </.simple_form>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  attr :member, :map, required: true
  attr :current_user, :map, required: true
  attr :role, :atom, required: true
  attr :household, :map, required: true

  defp member_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-200">
      <div class="card-body p-4">
        <div class="flex items-start justify-between">
          <div class="flex items-center gap-3">
            <%= if @member.user.avatar_url do %>
              <img
                src={@member.user.avatar_url}
                alt={@member.user.name || @member.user.email}
                class="w-12 h-12 rounded-full"
              />
            <% else %>
              <div class="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center">
                <span class="text-primary font-semibold text-lg">
                  <%= String.first(@member.user.name || @member.user.email) |> String.upcase() %>
                </span>
              </div>
            <% end %>
            <div>
              <p class="font-medium text-lg"><%= @member.user.name || @member.user.email %></p>
              <%= if @member.user.name do %>
                <p class="text-sm text-base-content/60"><%= @member.user.email %></p>
              <% end %>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <%= if @role == :admin && @member.user.id != @current_user.id do %>
              <select
                phx-change="change_role"
                phx-value-id={@member.membership_id}
                name="role"
                class="select select-bordered select-sm"
              >
                <option value="admin" selected={@member.role == :admin}>Admin</option>
                <option value="member" selected={@member.role == :member}>Member</option>
              </select>
            <% else %>
              <span class={[
                "badge",
                @member.role == :admin && "badge-primary",
                @member.role == :member && "badge-neutral"
              ]}>
                <%= @member.role %>
              </span>
            <% end %>
          </div>
        </div>

        <!-- Taste Profile Summary -->
        <%= if @member.taste_profile do %>
          <div class="mt-3 pt-3 border-t border-base-200">
            <div class="flex flex-wrap gap-2">
              <%= if @member.taste_profile.dietary_restrictions != [] do %>
                <%= for item <- @member.taste_profile.dietary_restrictions do %>
                  <span class="badge badge-outline badge-sm"><%= item %></span>
                <% end %>
              <% end %>
              <%= if @member.taste_profile.allergies != [] do %>
                <%= for item <- @member.taste_profile.allergies do %>
                  <span class="badge badge-error badge-outline badge-sm">⚠ <%= item %></span>
                <% end %>
              <% end %>
              <%= if @member.taste_profile.dietary_restrictions == [] && @member.taste_profile.allergies == [] do %>
                <span class="text-sm text-base-content/50">No dietary restrictions set</span>
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="mt-3 pt-3 border-t border-base-200">
            <span class="text-sm text-base-content/50">No taste profile yet</span>
          </div>
        <% end %>

        <!-- Actions -->
        <div class="mt-3 flex justify-end gap-2">
          <%= if @role == :admin || @member.user.id == @current_user.id do %>
            <button
              phx-click="edit_member"
              phx-value-id={@member.user.id}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-pencil" class="size-4 mr-1" />
              Edit Profile
            </button>
          <% end %>
          <%= if @role == :admin && @member.user.id != @current_user.id do %>
            <button
              phx-click="remove_member"
              phx-value-id={@member.membership_id}
              data-confirm="Are you sure you want to remove this member?"
              class="btn btn-ghost btn-sm text-error"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :field, :string, required: true
  attr :items, :list, required: true

  defp tag_section(assigns) do
    ~H"""
    <div class="space-y-2">
      <div>
        <h4 class="font-medium text-sm"><%= @title %></h4>
        <p class="text-xs text-base-content/60"><%= @description %></p>
      </div>

      <div class="flex flex-wrap gap-2">
        <%= for item <- @items do %>
          <span class="badge badge-lg gap-1">
            <%= item %>
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
          class="input input-bordered input-sm flex-1"
        />
        <button type="submit" class="btn btn-primary btn-sm">Add</button>
      </form>
    </div>
    """
  end
end
