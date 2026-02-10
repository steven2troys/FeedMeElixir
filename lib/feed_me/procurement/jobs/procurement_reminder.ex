defmodule FeedMe.Procurement.Jobs.ProcurementReminder do
  @moduledoc """
  Oban job that sends PubSub notifications for procurement plans
  that have been in :suggested status for more than 24 hours.
  """
  use Oban.Worker, queue: :procurement, max_attempts: 3

  alias FeedMe.Procurement

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"household_id" => household_id}}) do
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

    stale_plans =
      Procurement.list_plans(household_id, status: :suggested)
      |> Enum.filter(fn plan ->
        DateTime.compare(plan.inserted_at, cutoff) == :lt
      end)

    if stale_plans != [] do
      Phoenix.PubSub.broadcast(
        FeedMe.PubSub,
        "procurement:#{household_id}",
        {:procurement_reminder, stale_plans}
      )
    end

    :ok
  end
end
