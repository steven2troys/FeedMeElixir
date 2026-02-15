defmodule FeedMeWeb.HouseholdHooks do
  @moduledoc """
  LiveView hooks for household-scoped pages.
  """
  use FeedMeWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component

  alias FeedMe.Households
  alias FeedMe.Profiles

  def on_mount(:default, params, _session, socket) do
    household_id = params["household_id"] || params["id"]

    if household_id do
      user = socket.assigns.current_scope.user

      case Households.get_household_for_user(household_id, user) do
        nil ->
          {:halt,
           socket
           |> put_flash(:error, "Household not found or you don't have access")
           |> push_navigate(to: ~p"/")}

        %{household: household, role: role} ->
          nutrition_display = Profiles.get_nutrition_display(user.id, household.id)

          {:cont,
           socket
           |> assign(:household, household)
           |> assign(:role, role)
           |> assign(:nutrition_display, nutrition_display)
           |> FeedMeWeb.ChatDrawerHooks.attach_chat_drawer()
           |> FeedMeWeb.RestockHooks.attach_restock_hooks()}
      end
    else
      {:cont, socket}
    end
  end
end
