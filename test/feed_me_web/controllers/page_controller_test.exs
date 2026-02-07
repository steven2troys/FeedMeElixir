defmodule FeedMeWeb.PageControllerTest do
  use FeedMeWeb.ConnCase

  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures

  test "GET / redirects to login when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "GET / redirects to /households/new when user has 0 households", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    conn = conn |> log_in_user(user) |> get(~p"/")
    assert redirected_to(conn) == ~p"/households/new"
  end

  test "GET / redirects to household dashboard when user has 1 household", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    household = HouseholdsFixtures.household_fixture(%{}, user)
    conn = conn |> log_in_user(user) |> get(~p"/")
    assert redirected_to(conn) == ~p"/households/#{household.id}"
  end

  test "GET / redirects to /households when user has 2+ households", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    HouseholdsFixtures.household_fixture(%{name: "House 1"}, user)
    HouseholdsFixtures.household_fixture(%{name: "House 2"}, user)
    conn = conn |> log_in_user(user) |> get(~p"/")
    assert redirected_to(conn) == ~p"/households"
  end
end
