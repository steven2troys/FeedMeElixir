defmodule FeedMeWeb.ChatDrawerHooks do
  @moduledoc """
  Server-side hook logic for the ephemeral AI chat drawer.

  Called from HouseholdHooks to attach drawer assigns and event/info hooks
  to every LiveView in the household layout.
  """
  import Phoenix.LiveView
  require Logger

  alias FeedMe.AI

  @doc """
  Attaches drawer assigns and hooks to the socket.
  Called from HouseholdHooks.on_mount after household is loaded.
  """
  def attach_chat_drawer(socket) do
    household = socket.assigns[:household]
    has_api_key = household && AI.get_api_key(household.id) != nil

    socket
    |> Phoenix.Component.assign(:drawer_open, false)
    |> Phoenix.Component.assign(:drawer_messages, [])
    |> Phoenix.Component.assign(:drawer_input, "")
    |> Phoenix.Component.assign(:drawer_loading, false)
    |> Phoenix.Component.assign(:drawer_pending_image, nil)
    |> Phoenix.Component.assign(:drawer_has_api_key, has_api_key)
    |> Phoenix.Component.assign(:drawer_task_ref, nil)
    |> attach_hook(:drawer_events, :handle_event, &handle_event/3)
    |> attach_hook(:drawer_info, :handle_info, &handle_info/2)
  end

  # =============================================================================
  # Event Handlers
  # =============================================================================

  defp handle_event("drawer_toggle", _params, socket) do
    open = !socket.assigns.drawer_open

    socket =
      if open do
        Phoenix.Component.assign(socket, :drawer_open, true)
      else
        # Clear messages when closing
        socket
        |> Phoenix.Component.assign(:drawer_open, false)
        |> Phoenix.Component.assign(:drawer_messages, [])
        |> Phoenix.Component.assign(:drawer_input, "")
        |> Phoenix.Component.assign(:drawer_loading, false)
        |> Phoenix.Component.assign(:drawer_pending_image, nil)
      end

    {:halt, socket}
  end

  defp handle_event("drawer_send", %{"message" => message}, socket) when message != "" do
    household = socket.assigns.household
    user = socket.assigns.current_scope.user
    active_tab = socket.assigns[:active_tab]

    # Add user message to drawer
    user_msg = %{role: :user, content: message}
    messages = socket.assigns.drawer_messages ++ [user_msg]

    socket =
      socket
      |> Phoenix.Component.assign(:drawer_messages, messages)
      |> Phoenix.Component.assign(:drawer_input, "")
      |> Phoenix.Component.assign(:drawer_loading, true)

    # Fire async AI call
    context = %{
      household_id: household.id,
      user: user,
      page_context: active_tab
    }

    task =
      Task.Supervisor.async_nolink(FeedMe.Pantry.SyncTaskSupervisor, fn ->
        AI.ephemeral_chat(messages, context)
      end)

    socket = Phoenix.Component.assign(socket, :drawer_task_ref, task.ref)

    {:halt, socket}
  end

  defp handle_event("drawer_send", _params, socket) do
    {:halt, socket}
  end

  defp handle_event("drawer_update_input", %{"message" => value}, socket) do
    {:halt, Phoenix.Component.assign(socket, :drawer_input, value)}
  end

  defp handle_event("drawer_clear", _params, socket) do
    socket =
      socket
      |> Phoenix.Component.assign(:drawer_messages, [])
      |> Phoenix.Component.assign(:drawer_loading, false)
      |> Phoenix.Component.assign(:drawer_pending_image, nil)

    {:halt, socket}
  end

  defp handle_event("drawer_analyze_image", %{"type" => type}, socket) do
    image_data = socket.assigns.drawer_pending_image
    household = socket.assigns.household
    user = socket.assigns.current_scope.user
    active_tab = socket.assigns[:active_tab]

    user_msg = %{role: :user, content: "[Sent an image for analysis: #{type}]"}
    messages = socket.assigns.drawer_messages ++ [user_msg]

    context = %{
      household_id: household.id,
      user: user,
      page_context: active_tab,
      image: %{data: image_data, type: type}
    }

    socket =
      socket
      |> Phoenix.Component.assign(:drawer_messages, messages)
      |> Phoenix.Component.assign(:drawer_loading, true)
      |> Phoenix.Component.assign(:drawer_pending_image, nil)

    task =
      Task.Supervisor.async_nolink(FeedMe.Pantry.SyncTaskSupervisor, fn ->
        AI.ephemeral_chat(messages, context)
      end)

    socket = Phoenix.Component.assign(socket, :drawer_task_ref, task.ref)

    {:halt, socket}
  end

  defp handle_event("drawer_clear_image", _params, socket) do
    {:halt, Phoenix.Component.assign(socket, :drawer_pending_image, nil)}
  end

  # Pass through non-drawer events
  defp handle_event(_event, _params, socket) do
    {:cont, socket}
  end

  # =============================================================================
  # Info Handlers
  # =============================================================================

  # Task result: successful AI response
  defp handle_info({ref, {:ok, response}}, socket)
       when socket.assigns.drawer_task_ref == ref do
    Process.demonitor(ref, [:flush])

    assistant_msg = %{role: :assistant, content: response.content}
    messages = socket.assigns.drawer_messages ++ [assistant_msg]

    socket =
      socket
      |> Phoenix.Component.assign(:drawer_messages, messages)
      |> Phoenix.Component.assign(:drawer_loading, false)
      |> Phoenix.Component.assign(:drawer_task_ref, nil)

    {:halt, socket}
  end

  # Task result: error
  defp handle_info({ref, {:error, reason}}, socket)
       when socket.assigns.drawer_task_ref == ref do
    Process.demonitor(ref, [:flush])
    Logger.error("Drawer AI error: #{inspect(reason)}")

    error_msg = %{
      role: :assistant,
      content: "Sorry, I encountered an error. Please try again."
    }

    messages = socket.assigns.drawer_messages ++ [error_msg]

    socket =
      socket
      |> Phoenix.Component.assign(:drawer_messages, messages)
      |> Phoenix.Component.assign(:drawer_loading, false)
      |> Phoenix.Component.assign(:drawer_task_ref, nil)

    {:halt, socket}
  end

  # Task DOWN monitor (process crashed)
  defp handle_info({:DOWN, ref, :process, _pid, reason}, socket)
       when socket.assigns.drawer_task_ref == ref do
    Logger.error("Drawer AI task crashed: #{inspect(reason)}")

    error_msg = %{
      role: :assistant,
      content: "Sorry, something went wrong. Please try again."
    }

    messages = socket.assigns.drawer_messages ++ [error_msg]

    socket =
      socket
      |> Phoenix.Component.assign(:drawer_messages, messages)
      |> Phoenix.Component.assign(:drawer_loading, false)
      |> Phoenix.Component.assign(:drawer_task_ref, nil)

    {:halt, socket}
  end

  # Voice transcription — route to drawer when open
  defp handle_info({:voice_transcribed, text}, socket)
       when socket.assigns.drawer_open do
    # Simulate a send by putting the text in input and triggering send
    {:halt,
     socket
     |> Phoenix.Component.assign(:drawer_input, text)
     |> then(&handle_drawer_voice_send(&1, text))}
  end

  # Image selected — route to drawer when open
  defp handle_info({:image_selected, image_data}, socket)
       when socket.assigns.drawer_open do
    {:halt, Phoenix.Component.assign(socket, :drawer_pending_image, image_data)}
  end

  # Pass through non-drawer info messages
  defp handle_info(_msg, socket) do
    {:cont, socket}
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp handle_drawer_voice_send(socket, text) do
    household = socket.assigns.household
    user = socket.assigns.current_scope.user
    active_tab = socket.assigns[:active_tab]

    user_msg = %{role: :user, content: text}
    messages = socket.assigns.drawer_messages ++ [user_msg]

    context = %{
      household_id: household.id,
      user: user,
      page_context: active_tab
    }

    socket =
      socket
      |> Phoenix.Component.assign(:drawer_messages, messages)
      |> Phoenix.Component.assign(:drawer_input, "")
      |> Phoenix.Component.assign(:drawer_loading, true)

    task =
      Task.Supervisor.async_nolink(FeedMe.Pantry.SyncTaskSupervisor, fn ->
        AI.ephemeral_chat(messages, context)
      end)

    Phoenix.Component.assign(socket, :drawer_task_ref, task.ref)
  end
end
