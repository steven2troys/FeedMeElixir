defmodule FeedMeWeb.HouseholdHooks do
  @moduledoc """
  LiveView hooks for household-scoped pages.
  """
  use FeedMeWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component

  alias FeedMe.Households

  def on_mount(:default, params, _session, socket) do
    household_id = params["household_id"] || params["id"]

    if household_id do
      user = socket.assigns.current_scope.user

      case Households.get_household_for_user(household_id, user) do
        nil ->
          {:halt,
           socket
           |> put_flash(:error, "Household not found or you don't have access")
           |> push_navigate(to: ~p"/households")}

        %{household: household, role: role} ->
          {:cont,
           socket
           |> assign(:household, household)
           |> assign(:role, role)
           |> FeedMeWeb.ChatDrawerHooks.attach_chat_drawer()}
      end
    else
      {:cont, socket}
    end
  end
end
