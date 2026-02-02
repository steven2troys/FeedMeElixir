defmodule FeedMeWeb.PageController do
  use FeedMeWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_scope] do
      redirect(conn, to: ~p"/households")
    else
      redirect(conn, to: ~p"/users/log-in")
    end
  end
end
