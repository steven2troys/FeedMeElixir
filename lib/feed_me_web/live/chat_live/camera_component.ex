defmodule FeedMeWeb.ChatLive.CameraComponent do
  @moduledoc """
  Live component for camera capture and image upload.
  """
  use FeedMeWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook="Camera" class="relative">
      <%= if @mode == :idle do %>
        <div class="flex gap-2">
          <button
            type="button"
            phx-click="start_camera"
            phx-target={@myself}
            class="btn btn-circle btn-ghost"
            aria-label="Take photo"
          >
            <.icon name="hero-camera" class="size-5" />
          </button>

          <label class="btn btn-circle btn-ghost cursor-pointer" aria-label="Upload image">
            <.icon name="hero-photo" class="size-5" />
            <input
              type="file"
              accept="image/*"
              class="hidden"
            />
          </label>
        </div>
      <% end %>

      <%= if @mode == :camera do %>
        <div class="fixed inset-0 z-50 bg-black flex flex-col">
          <div class="flex-1 relative">
            <video autoplay playsinline class="w-full h-full object-cover"></video>
            <canvas class="hidden"></canvas>
          </div>
          <div class="p-4 flex justify-center gap-4 bg-black/50">
            <button
              type="button"
              phx-click="stop_camera"
              phx-target={@myself}
              class="btn btn-circle btn-ghost text-white"
            >
              <.icon name="hero-x-mark" class="size-6" />
            </button>
            <button
              type="button"
              data-capture
              class="btn btn-circle btn-lg btn-primary"
            >
              <.icon name="hero-camera" class="size-8" />
            </button>
          </div>
        </div>
      <% end %>

      <%= if @mode == :preview && @preview_image do %>
        <div class="fixed inset-0 z-50 bg-black flex flex-col">
          <div class="flex-1 relative overflow-hidden">
            <img src={@preview_image} class="w-full h-full object-contain" alt="Preview" />
          </div>
          <div class="p-4 flex justify-center gap-4 bg-black/50">
            <button
              type="button"
              phx-click="discard_image"
              phx-target={@myself}
              class="btn btn-ghost text-white"
            >
              Retake
            </button>
            <button
              type="button"
              phx-click="use_image"
              phx-target={@myself}
              class="btn btn-primary"
            >
              Use Photo
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:mode, :idle)
     |> assign(:preview_image, nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("start_camera", _params, socket) do
    {:noreply, push_event(socket, "start_camera", %{}) |> assign(:mode, :camera)}
  end

  def handle_event("stop_camera", _params, socket) do
    {:noreply, push_event(socket, "stop_camera", %{}) |> assign(:mode, :idle)}
  end

  def handle_event("image_captured", %{"image" => image}, socket) do
    {:noreply, assign(socket, mode: :preview, preview_image: image)}
  end

  def handle_event("image_uploaded", %{"image" => image}, socket) do
    {:noreply, assign(socket, mode: :preview, preview_image: image)}
  end

  def handle_event("discard_image", _params, socket) do
    {:noreply, assign(socket, mode: :idle, preview_image: nil)}
  end

  def handle_event("use_image", _params, socket) do
    send(self(), {:image_selected, socket.assigns.preview_image})
    {:noreply, assign(socket, mode: :idle, preview_image: nil)}
  end

  def handle_event("camera_error", %{"error" => error}, socket) do
    send(self(), {:camera_error, error})
    {:noreply, assign(socket, :mode, :idle)}
  end
end
