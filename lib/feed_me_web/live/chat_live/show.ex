defmodule FeedMeWeb.ChatLive.Show do
  @moduledoc """
  LiveView for a single AI chat conversation.
  """
  use FeedMeWeb, :live_view

  alias FeedMe.AI
  alias FeedMe.AI.Vision
  alias FeedMeWeb.ChatLive.{VoiceButtonComponent, CameraComponent}

  @impl true
  def mount(%{"id" => conversation_id}, _session, socket) do
    # household and role are set by HouseholdHooks
    household = socket.assigns.household
    conversation = AI.get_conversation(conversation_id, household.id)

    if conversation do
      {:ok,
       socket
       |> assign(:active_tab, :chat)
       |> assign(:conversation, conversation)
       |> assign(:messages, conversation.messages || [])
       |> assign(:input, "")
       |> assign(:loading, false)
       |> assign(:streaming_content, "")
       |> assign(:pending_image, nil)
       |> assign(:page_title, conversation.title || "Chat")}
    else
      {:ok,
       socket
       |> put_flash(:error, "Conversation not found")
       |> push_navigate(to: ~p"/households/#{household.id}/chat")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    send_message(socket, message)
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  def handle_event("analyze_image", %{"type" => type}, socket) do
    case socket.assigns.pending_image do
      nil ->
        {:noreply, put_flash(socket, :error, "No image to analyze")}

      image_data ->
        analyze_pending_image(socket, type, image_data)
    end
  end

  def handle_event("clear_image", _params, socket) do
    {:noreply, assign(socket, :pending_image, nil)}
  end

  def handle_event("new_chat", _params, socket) do
    user = socket.assigns.current_scope.user
    household = socket.assigns.household

    case AI.create_conversation(household.id, user) do
      {:ok, conversation} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/households/#{household.id}/chat/#{conversation.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create new chat")}
    end
  end

  @impl true
  def handle_info({:send_to_ai, message, context}, socket) do
    conversation = socket.assigns.conversation

    case AI.chat(conversation, message, context) do
      {:ok, _assistant_msg} ->
        # Reload conversation to get all messages
        conversation = AI.get_conversation(conversation.id)

        {:noreply,
         socket
         |> assign(:conversation, conversation)
         |> assign(:messages, conversation.messages)
         |> assign(:loading, false)
         |> assign(:streaming_content, "")}

      {:error, :no_api_key} ->
        {:noreply,
         socket
         |> put_flash(:error, "No API key configured. Please add your OpenRouter API key.")
         |> assign(:loading, false)}

      {:error, :invalid_api_key} ->
        {:noreply,
         socket
         |> put_flash(:error, "API key is invalid. Please update your OpenRouter API key.")
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Error: #{inspect(reason)}")
         |> assign(:loading, false)}
    end
  end

  # Voice input handlers
  def handle_info({:voice_transcribed, text}, socket) do
    # Use the transcribed text as the message
    send_message(socket, text)
  end

  def handle_info({:voice_audio_data, _audio}, socket) do
    # For now, just inform user that native speech recognition is preferred
    {:noreply, put_flash(socket, :info, "Voice input processed")}
  end

  def handle_info({:voice_error, error}, socket) do
    {:noreply, put_flash(socket, :error, "Voice error: #{error}")}
  end

  # Camera handlers
  def handle_info({:image_selected, image_data}, socket) do
    {:noreply, assign(socket, :pending_image, image_data)}
  end

  def handle_info({:camera_error, error}, socket) do
    {:noreply, put_flash(socket, :error, "Camera error: #{error}")}
  end

  def handle_info({:analyze_image, type, image_data, household_id}, socket) do
    result =
      case type do
        "fridge" -> Vision.analyze_fridge(household_id, image_data)
        "macros" -> Vision.analyze_dish_macros(household_id, image_data)
        "recipe" -> Vision.digitize_recipe(household_id, image_data)
        "identify" -> Vision.identify_food(household_id, image_data)
        _ -> {:error, "Unknown analysis type"}
      end

    case result do
      {:ok, analysis} ->
        # Add the analysis as an assistant message
        analysis_result = %{
          id: Ecto.UUID.generate(),
          role: :assistant,
          content: analysis,
          inserted_at: DateTime.utc_now()
        }

        {:noreply,
         socket
         |> update(:messages, &(&1 ++ [analysis_result]))
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Image analysis failed: #{inspect(reason)}")
         |> assign(:loading, false)}
    end
  end

  defp send_message(socket, message) do
    user = socket.assigns.current_scope.user
    household = socket.assigns.household

    # Build context for tool execution
    context = %{
      household_id: household.id,
      user: user
    }

    # Add user message to UI immediately
    user_msg = %{
      id: Ecto.UUID.generate(),
      role: :user,
      content: message,
      inserted_at: DateTime.utc_now()
    }

    socket =
      socket
      |> update(:messages, &(&1 ++ [user_msg]))
      |> assign(:input, "")
      |> assign(:loading, true)

    # Send message to AI in background
    send(self(), {:send_to_ai, message, context})

    {:noreply, socket}
  end

  defp analyze_pending_image(socket, type, image_data) do
    household = socket.assigns.household

    # Add a message indicating image analysis
    analysis_msg = %{
      id: Ecto.UUID.generate(),
      role: :user,
      content: "[Analyzing image: #{type}]",
      inserted_at: DateTime.utc_now()
    }

    socket =
      socket
      |> update(:messages, &(&1 ++ [analysis_msg]))
      |> assign(:loading, true)
      |> assign(:pending_image, nil)

    # Perform analysis in background
    send(self(), {:analyze_image, type, image_data, household.id})

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl h-[calc(100vh-200px)] flex flex-col">
      <.header>
        <%= @conversation.title || "New Chat" %>
        <:actions>
          <button phx-click="new_chat" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4 mr-1" /> New Chat
          </button>
          <.link navigate={~p"/households/#{@household.id}/chat"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="size-4 mr-1" /> All Chats
          </.link>
        </:actions>
      </.header>

      <div class="flex-1 overflow-y-auto mt-4 space-y-4 pb-4" id="messages">
        <%= for message <- @messages do %>
          <.message_bubble message={message} />
        <% end %>

        <%= if @loading do %>
          <div class="chat chat-start">
            <div class="chat-bubble bg-base-200 text-base-content">
              <span class="loading loading-dots loading-sm"></span>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @pending_image do %>
        <div class="p-4 border-t border-base-200 bg-base-200/50">
          <div class="flex items-center gap-4">
            <img src={@pending_image} class="w-20 h-20 object-cover rounded" alt="Pending" />
            <div class="flex-1">
              <p class="text-sm font-medium mb-2">What would you like to do with this image?</p>
              <div class="flex flex-wrap gap-2">
                <button phx-click="analyze_image" phx-value-type="fridge" class="btn btn-sm">
                  Scan Fridge
                </button>
                <button phx-click="analyze_image" phx-value-type="macros" class="btn btn-sm">
                  Estimate Macros
                </button>
                <button phx-click="analyze_image" phx-value-type="recipe" class="btn btn-sm">
                  Digitize Recipe
                </button>
                <button phx-click="analyze_image" phx-value-type="identify" class="btn btn-sm">
                  Identify Food
                </button>
                <button phx-click="clear_image" class="btn btn-sm btn-ghost">
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <div class="sticky bottom-0 bg-base-100 pt-4 border-t border-base-200">
        <form phx-submit="send_message" class="flex gap-2 items-center">
          <.live_component
            module={VoiceButtonComponent}
            id="voice-input"
            recording={false}
          />

          <.live_component
            module={CameraComponent}
            id="camera-input"
          />

          <input
            type="text"
            name="message"
            value={@input}
            phx-change="update_input"
            placeholder="Ask me about recipes, shopping, pantry..."
            class="input input-bordered flex-1"
            autocomplete="off"
            disabled={@loading}
          />
          <button type="submit" class="btn btn-primary" disabled={@loading || @input == ""}>
            <.icon name="hero-paper-airplane" class="size-5" />
          </button>
        </form>
        <p class="text-xs text-base-content/50 mt-2 text-center">
          AI can make mistakes. Verify important information.
        </p>
      </div>
    </div>
    """
  end

  defp message_bubble(assigns) do
    ~H"""
    <div class={["chat", @message.role == :user && "chat-end", @message.role != :user && "chat-start"]}>
      <%= if @message.role == :tool do %>
        <div class="chat-bubble bg-base-300 text-base-content text-sm p-0 overflow-hidden">
          <details class="collapse collapse-arrow bg-base-300">
            <summary class="collapse-title min-h-0 py-2 px-4 text-xs font-medium">
              <.icon name="hero-magnifying-glass" class="size-3 inline mr-1" />
              Web Search Results
            </summary>
            <div class="collapse-content px-4 pb-3">
              <div class="whitespace-pre-wrap text-xs opacity-90"><%= @message.content %></div>
            </div>
          </details>
        </div>
      <% else %>
        <div class={[
          "chat-bubble",
          @message.role == :user && "chat-bubble-primary",
          @message.role == :assistant && "bg-base-200 text-base-content"
        ]}>
          <div class="whitespace-pre-wrap"><%= @message.content %></div>
        </div>
      <% end %>
    </div>
    """
  end
end
