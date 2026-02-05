defmodule FeedMeWeb.ChatLive.Index do
  @moduledoc """
  LiveView for AI chat conversations.
  """
  use FeedMeWeb, :live_view

  alias FeedMe.AI

  @impl true
  def mount(_params, _session, socket) do
    # household and role are set by HouseholdHooks
    household = socket.assigns.household

    conversations = AI.list_conversations(household.id)
    api_key = AI.get_api_key(household.id)

    {:ok,
     socket
     |> assign(:active_tab, :chat)
     |> assign(:conversations, conversations)
     |> assign(:has_api_key, api_key != nil && api_key.is_valid)
     |> assign(:page_title, "AI Chat")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:conversation, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:conversation, nil)
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    user = socket.assigns.current_scope.user

    case AI.create_conversation(socket.assigns.household.id, user) do
      {:ok, conversation} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/households/#{socket.assigns.household.id}/chat/#{conversation.id}"
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create conversation")}
    end
  end

  def handle_event("archive_conversation", %{"id" => id}, socket) do
    case AI.get_conversation(id, socket.assigns.household.id) do
      nil ->
        {:noreply, socket}

      conversation ->
        {:ok, _} = AI.archive_conversation(conversation)
        conversations = AI.list_conversations(socket.assigns.household.id)
        {:noreply, assign(socket, :conversations, conversations)}
    end
  end

  def handle_event("delete_conversation", %{"id" => id}, socket) do
    case AI.get_conversation(id, socket.assigns.household.id) do
      nil ->
        {:noreply, socket}

      conversation ->
        {:ok, _} = AI.delete_conversation(conversation)
        conversations = AI.list_conversations(socket.assigns.household.id)

        {:noreply,
         socket
         |> assign(:conversations, conversations)
         |> put_flash(:info, "Conversation deleted")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <.header>
        AI Chat
        <:subtitle>Get help from your AI assistant</:subtitle>
        <:actions>
          <%= if @has_api_key do %>
            <.button phx-click="new_conversation">
              <.icon name="hero-plus" class="size-4 mr-1" /> New Chat
            </.button>
          <% else %>
            <.link navigate={~p"/households/#{@household.id}/settings/api-key"}>
              <.button>Set Up API Key</.button>
            </.link>
          <% end %>
        </:actions>
      </.header>

      <%= if !@has_api_key do %>
        <div class="mt-6 alert alert-warning">
          <.icon name="hero-exclamation-triangle" class="size-6" />
          <div>
            <h3 class="font-bold">API Key Required</h3>
            <p class="text-sm">
              To use AI features, you need to add your OpenRouter API key.
              <%= if @role == :admin do %>
                <.link navigate={~p"/households/#{@household.id}/settings/api-key"} class="link">
                  Add API Key
                </.link>
              <% else %>
                Ask a household admin to set this up.
              <% end %>
            </p>
          </div>
        </div>
      <% end %>

      <%= if @has_api_key do %>
        <div class="mt-6">
          <%= if @conversations == [] do %>
            <div class="text-center py-12 text-base-content/60">
              <.icon name="hero-chat-bubble-left-right" class="size-12 mx-auto mb-4" />
              <p>No conversations yet.</p>
              <p class="text-sm mt-2">Start a new chat to get help with meal planning, shopping, and more.</p>
            </div>
          <% else %>
            <div class="space-y-2">
              <%= for conversation <- @conversations do %>
                <div class="card bg-base-100 border border-base-200 hover:border-primary transition-colors">
                  <div class="card-body p-4 flex-row items-center justify-between">
                    <.link
                      navigate={~p"/households/#{@household.id}/chat/#{conversation.id}"}
                      class="flex-1"
                    >
                      <h3 class="font-medium">
                        <%= conversation.title || "New conversation" %>
                      </h3>
                      <p class="text-sm text-base-content/60">
                        <%= Calendar.strftime(conversation.updated_at, "%b %d, %Y at %I:%M %p") %>
                      </p>
                    </.link>
                    <div class="flex gap-1">
                      <button
                        phx-click="archive_conversation"
                        phx-value-id={conversation.id}
                        class="btn btn-ghost btn-sm"
                        title="Archive"
                      >
                        <.icon name="hero-archive-box" class="size-4" />
                      </button>
                      <button
                        phx-click="delete_conversation"
                        phx-value-id={conversation.id}
                        data-confirm="Delete this conversation? This cannot be undone."
                        class="btn btn-ghost btn-sm text-error"
                        title="Delete"
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <.back navigate={~p"/households/#{@household.id}"}>Back to household</.back>
    </div>
    """
  end
end
