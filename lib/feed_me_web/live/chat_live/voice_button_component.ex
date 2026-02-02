defmodule FeedMeWeb.ChatLive.VoiceButtonComponent do
  @moduledoc """
  Live component for voice input button with tap-to-talk functionality.
  """
  use FeedMeWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-hook="VoiceInput"
      phx-target={@myself}
      class={[
        "btn btn-circle btn-ghost",
        @recording && "btn-error animate-pulse"
      ]}
      aria-label={if @recording, do: "Stop recording", else: "Start voice input"}
    >
      <%= if @recording do %>
        <.icon name="hero-stop" class="size-5" />
      <% else %>
        <.icon name="hero-microphone" class="size-5" />
      <% end %>
    </button>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:recording, false)
     |> assign(:interim_text, nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("voice_recording_started", _params, socket) do
    {:noreply, assign(socket, :recording, true)}
  end

  def handle_event("voice_recording_stopped", _params, socket) do
    {:noreply, assign(socket, recording: false, interim_text: nil)}
  end

  def handle_event("voice_interim", %{"text" => text}, socket) do
    {:noreply, assign(socket, :interim_text, text)}
  end

  def handle_event("voice_transcribed", %{"text" => text}, socket) do
    send(self(), {:voice_transcribed, text})
    {:noreply, assign(socket, recording: false, interim_text: nil)}
  end

  def handle_event("voice_audio_data", %{"audio" => audio}, socket) do
    # Send to parent for Whisper processing if needed
    send(self(), {:voice_audio_data, audio})
    {:noreply, socket}
  end

  def handle_event("voice_error", %{"error" => error}, socket) do
    send(self(), {:voice_error, error})
    {:noreply, assign(socket, recording: false)}
  end
end
