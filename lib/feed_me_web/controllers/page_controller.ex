defmodule FeedMeWeb.PageController do
  use FeedMeWeb, :controller

  alias FeedMe.Households

  def home(conn, _params) do
    if conn.assigns[:current_scope] do
      user = conn.assigns.current_scope.user

      case Households.get_single_household_for_user(user) do
        %{id: id} ->
          redirect(conn, to: ~p"/households/#{id}")

        nil ->
          if Households.count_households_for_user(user) == 0 do
            redirect(conn, to: ~p"/households/new")
          else
            redirect(conn, to: ~p"/households")
          end
      end
    else
      redirect(conn, to: ~p"/users/log-in")
    end
  end
end
