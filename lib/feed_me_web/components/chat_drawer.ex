defmodule FeedMeWeb.ChatDrawer do
  @moduledoc """
  Function component for the ephemeral AI chat drawer.
  Renders a FAB button and a sliding right-side panel for quick AI interactions.
  """
  use Phoenix.Component

  import FeedMeWeb.CoreComponents

  alias FeedMeWeb.ChatLive.{VoiceButtonComponent, CameraComponent}

  attr :drawer_open, :boolean, default: false
  attr :drawer_messages, :list, default: []
  attr :drawer_input, :string, default: ""
  attr :drawer_loading, :boolean, default: false
  attr :drawer_pending_image, :string, default: nil
  attr :drawer_has_api_key, :boolean, default: false
  attr :household, :map, required: true
  attr :active_tab, :atom, default: nil

  def chat_drawer(assigns) do
    ~H"""
    <%!-- FAB Button --%>
    <button
      :if={not @drawer_open}
      phx-click="drawer_toggle"
      class="hidden md:flex fixed bottom-6 right-6 z-40 btn btn-primary btn-circle shadow-lg size-14"
      aria-label="Open AI assistant"
    >
      <.icon name="hero-chat-bubble-left-ellipsis" class="size-6" />
    </button>

    <%!-- Drawer backdrop --%>
    <div
      :if={@drawer_open}
      phx-click="drawer_toggle"
      class="fixed inset-0 z-40 bg-black/20 md:hidden"
    />

    <%!-- Drawer panel --%>
    <div
      id="chat-drawer"
      phx-hook="ChatDrawer"
      class={[
        "fixed top-[65px] right-0 bottom-0 w-full md:w-96 md:max-w-[calc(100vw-3rem)] z-50",
        "bg-base-100 border-l border-base-300 shadow-xl",
        "flex flex-col",
        "transition-transform duration-300 ease-in-out",
        @drawer_open && "translate-x-0 pointer-events-auto",
        not @drawer_open && "translate-x-full pointer-events-none"
      ]}
    >
      <%!-- Header --%>
      <div class="flex items-center justify-between px-4 py-3 border-b border-base-300 bg-base-200/50">
        <div class="flex items-center gap-2">
          <.icon name="hero-sparkles" class="size-5 text-primary" />
          <span class="font-semibold text-sm">{drawer_title(@active_tab)}</span>
        </div>
        <div class="flex items-center gap-1">
          <button
            :if={@drawer_messages != []}
            phx-click="drawer_clear"
            class="btn btn-ghost btn-xs"
            aria-label="Clear messages"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
          <button
            phx-click="drawer_toggle"
            class="btn btn-ghost btn-xs"
            aria-label="Close drawer"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
      </div>

      <%!-- Messages --%>
      <div id="drawer-messages" class="flex-1 overflow-y-auto p-4 space-y-3" phx-update="replace">
        <%= if @drawer_messages == [] and not @drawer_loading do %>
          <div class="flex flex-col items-center justify-center h-full text-base-content/50 text-sm text-center px-4">
            <.icon name="hero-sparkles" class="size-8 mb-3 opacity-50" />
            <p class="font-medium mb-1">{drawer_hint(@active_tab)}</p>
            <p class="text-xs">Messages are ephemeral and won't be saved.</p>
          </div>
        <% end %>

        <%= for {msg, idx} <- Enum.with_index(@drawer_messages) do %>
          <.drawer_message_bubble message={msg} idx={idx} />
        <% end %>

        <%= if @drawer_loading do %>
          <div class="chat chat-start">
            <div class="chat-bubble bg-base-200 text-base-content text-sm py-2 px-3">
              <span class="loading loading-dots loading-xs"></span>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Pending image --%>
      <%= if @drawer_pending_image do %>
        <div class="px-4 py-3 border-t border-base-200 bg-base-200/50">
          <div class="flex items-center gap-3">
            <img src={@drawer_pending_image} class="w-16 h-16 object-cover rounded" alt="Pending" />
            <div class="flex-1">
              <p class="text-xs font-medium mb-1">Analyze this image:</p>
              <div class="flex flex-wrap gap-1">
                <button phx-click="drawer_analyze_image" phx-value-type="fridge" class="btn btn-xs">
                  Scan Fridge
                </button>
                <button phx-click="drawer_analyze_image" phx-value-type="identify" class="btn btn-xs">
                  Identify
                </button>
                <button phx-click="drawer_clear_image" class="btn btn-xs btn-ghost">
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- No API key notice --%>
      <%= if not @drawer_has_api_key do %>
        <div class="px-4 py-3 border-t border-base-200">
          <div class="alert alert-warning text-xs py-2">
            <.icon name="hero-exclamation-triangle" class="size-4" />
            <span>
              Set up an API key in
              <.link
                navigate={"/households/#{@household.id}/settings/api-key"}
                class="link font-medium"
              >
                Settings
              </.link>
              to use AI features.
            </span>
          </div>
        </div>
      <% end %>

      <%!-- Input area --%>
      <div class="px-3 py-3 pb-16 md:pb-3 border-t border-base-300 bg-base-100">
        <form phx-submit="drawer_send" class="flex gap-2 items-center">
          <.live_component
            module={VoiceButtonComponent}
            id="drawer-voice-input"
            recording={false}
          />

          <.live_component
            module={CameraComponent}
            id="drawer-camera-input"
          />

          <input
            type="text"
            name="message"
            value={@drawer_input}
            phx-change="drawer_update_input"
            placeholder={drawer_placeholder(@active_tab)}
            class="input input-bordered input-sm flex-1"
            autocomplete="off"
            disabled={@drawer_loading or not @drawer_has_api_key}
          />
          <button
            type="submit"
            class="btn btn-primary btn-sm btn-circle"
            disabled={@drawer_loading or @drawer_input == "" or not @drawer_has_api_key}
          >
            <.icon name="hero-paper-airplane" class="size-4" />
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp drawer_message_bubble(assigns) do
    ~H"""
    <div
      id={"drawer-msg-#{@idx}"}
      class={["chat", @message.role == :user && "chat-end", @message.role != :user && "chat-start"]}
    >
      <div class={[
        "chat-bubble text-sm",
        @message.role == :user && "chat-bubble-primary",
        @message.role == :assistant && "bg-base-200 text-base-content"
      ]}>
        <div class="whitespace-pre-wrap">{@message.content}</div>
      </div>
    </div>
    """
  end

  defp drawer_title(:pantry), do: "Pantry Assistant"
  defp drawer_title(:shopping), do: "Shopping Assistant"
  defp drawer_title(:recipes), do: "Recipe Assistant"
  defp drawer_title(_), do: "AI Assistant"

  defp drawer_hint(:pantry), do: "Tell me what you bought or what's in your fridge"
  defp drawer_hint(:shopping), do: "Tell me what you need to buy"
  defp drawer_hint(:recipes), do: "Ask me to find or suggest recipes"
  defp drawer_hint(_), do: "How can I help you today?"

  defp drawer_placeholder(:pantry), do: "e.g. Add 2 gallons of milk..."
  defp drawer_placeholder(:shopping), do: "e.g. Add eggs and butter..."
  defp drawer_placeholder(:recipes), do: "e.g. Suggest dinner with chicken..."
  defp drawer_placeholder(_), do: "Ask me anything..."
end
