defmodule FeedMe.Scheduler do
  @moduledoc """
  Periodically enqueues household-specific Oban jobs based on each
  household's schedule settings and automation tier.

  This module is called by Oban's cron plugin to run a dispatcher
  that fans out per-household jobs.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query
  alias FeedMe.Repo
  alias FeedMe.Households.Household

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "weekly_suggestion"}}) do
    today_day_of_week = Date.day_of_week(Date.utc_today())

    Household
    |> where([h], h.automation_tier != :off)
    |> where([h], h.weekly_suggestion_enabled == true)
    |> where([h], h.weekly_suggestion_day == ^today_day_of_week)
    |> select([h], h.id)
    |> Repo.all()
    |> Enum.each(fn household_id ->
      %{household_id: household_id}
      |> FeedMe.MealPlanning.Jobs.WeeklySuggestion.new()
      |> Oban.insert()
    end)

    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "daily_pantry_check"}}) do
    Household
    |> where([h], h.automation_tier != :off)
    |> where([h], h.daily_pantry_check_enabled == true)
    |> select([h], h.id)
    |> Repo.all()
    |> Enum.each(fn household_id ->
      %{household_id: household_id}
      |> FeedMe.Procurement.Jobs.DailyPantryCheck.new()
      |> Oban.insert()
    end)

    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "procurement_reminder"}}) do
    Household
    |> where([h], h.automation_tier != :off)
    |> select([h], h.id)
    |> Repo.all()
    |> Enum.each(fn household_id ->
      %{household_id: household_id}
      |> FeedMe.Procurement.Jobs.ProcurementReminder.new()
      |> Oban.insert()
    end)

    :ok
  end
end
