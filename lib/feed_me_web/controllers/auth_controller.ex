defmodule FeedMeWeb.AuthController do
  use FeedMeWeb, :controller

  plug Ueberauth

  alias FeedMe.Accounts
  alias FeedMeWeb.UserAuth

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate with Google.")
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_params = %{
      email: auth.info.email,
      google_id: auth.uid,
      name: auth.info.name,
      avatar_url: auth.info.image
    }

    case Accounts.find_or_create_user_from_google(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome, #{user.name || user.email}!")
        |> UserAuth.log_in_user(user)

      {:error, :email_already_taken} ->
        conn
        |> put_flash(:error, "This email is already associated with another account.")
        |> redirect(to: ~p"/users/log-in")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to create account. Please try again.")
        |> redirect(to: ~p"/users/log-in")
    end
  end
end
