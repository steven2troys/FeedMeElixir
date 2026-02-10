defmodule FeedMe.Procurement.Jobs.DailyPantryCheck do
  @moduledoc """
  Oban job that checks for items needing restock or expiring soon,
  and creates procurement recommendations for eligible households.
  """
  use Oban.Worker, queue: :procurement, max_attempts: 3

  alias FeedMe.{Households, Pantry, Procurement}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"household_id" => household_id}}) do
    household = Households.get_household(household_id)

    if household && household.automation_tier in [:recommend, :cart_fill, :auto_purchase] do
      check_and_create_recommendations(household)
    else
      :ok
    end
  end

  defp check_and_create_recommendations(household) do
    restock_items = Pantry.items_needing_restock(household.id)
    expiring_items = Pantry.items_expiring_soon(household.id, 7)

    # Only create a plan if there are items to procure
    # and no existing suggested plan from today
    existing_today =
      Procurement.list_plans(household.id, status: :suggested)
      |> Enum.any?(fn plan ->
        Date.compare(DateTime.to_date(plan.inserted_at), Date.utc_today()) == :eq
      end)

    if (restock_items != [] or expiring_items != []) and not existing_today do
      # Create a combined restock + expiring plan
      # Use a system user placeholder (first admin)
      case get_admin_user(household) do
        nil ->
          :ok

        user ->
          if restock_items != [] do
            Procurement.create_from_restock(household.id, user)
          end

          if expiring_items != [] do
            Procurement.create_from_expiring(household.id, user)
          end

          :ok
      end
    else
      :ok
    end
  end

  defp get_admin_user(household) do
    household = FeedMe.Repo.preload(household, memberships: :user)

    case Enum.find(household.memberships, &(&1.role == :admin)) do
      nil -> nil
      membership -> membership.user
    end
  end
end
