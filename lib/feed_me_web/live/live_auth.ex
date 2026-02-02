defmodule FeedMeWeb.LiveAuth do
  @moduledoc """
  LiveView authentication hook to assign current_scope to socket.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias FeedMe.Accounts
  alias FeedMe.Accounts.Scope

  def on_mount(:default, _params, session, socket) do
    socket = assign_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/users/log-in")}
    end
  end

  def on_mount(:allow_unauthenticated, _params, session, socket) do
    {:cont, assign_current_scope(socket, session)}
  end

  defp assign_current_scope(socket, session) do
    case session["user_token"] do
      nil ->
        assign(socket, :current_scope, Scope.for_user(nil))

      token ->
        case Accounts.get_user_by_session_token(token) do
          {user, _inserted_at} ->
            assign(socket, :current_scope, Scope.for_user(user))

          nil ->
            assign(socket, :current_scope, Scope.for_user(nil))
        end
    end
  end
end
