defmodule FeedMeWeb.Plugs.NavContext do
  @moduledoc """
  Sets navigation context assigns for the root layout based on the current route.

  Extracts household ID from path params and loads the current user's membership
  so the root layout can render household-aware navigation links.
  """
  import Plug.Conn

  alias FeedMe.Households

  def init(opts), do: opts

  def call(conn, _opts) do
    household_id = conn.path_params["household_id"] || conn.path_params["id"]
    user = conn.assigns[:current_scope] && conn.assigns[:current_scope].user

    if household_id && user do
      case Households.get_membership(user.id, household_id) do
        %{role: role} ->
          conn
          |> assign(:nav_household_id, household_id)
          |> assign(:nav_is_admin, role == :admin)

        nil ->
          assign_no_household_context(conn)
      end
    else
      assign_no_household_context(conn)
    end
  end

  defp assign_no_household_context(conn) do
    conn
    |> assign(:nav_household_id, nil)
    |> assign(:nav_is_admin, false)
  end
end
