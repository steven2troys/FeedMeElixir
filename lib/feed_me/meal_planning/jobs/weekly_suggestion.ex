defmodule FeedMe.MealPlanning.Jobs.WeeklySuggestion do
  @moduledoc """
  Oban job that generates a draft meal plan for the upcoming week
  for households with automation_tier >= :recommend.
  """
  use Oban.Worker, queue: :meal_planning, max_attempts: 3

  alias FeedMe.{Households, MealPlanning, Recipes}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"household_id" => household_id}}) do
    household = Households.get_household(household_id)

    if household && household.automation_tier in [:recommend, :cart_fill, :auto_purchase] do
      generate_suggestion(household)
    else
      :ok
    end
  end

  defp generate_suggestion(household) do
    recipes = Recipes.list_recipes(household.id)

    if recipes == [] do
      :ok
    else
      # Calculate next week's Monday through Sunday
      today = today_for_household(household)
      days_until_monday = rem(8 - Date.day_of_week(today), 7)
      days_until_monday = if days_until_monday == 0, do: 7, else: days_until_monday
      start_date = Date.add(today, days_until_monday)
      end_date = Date.add(start_date, 6)

      # Check if a plan already exists for this period
      existing =
        MealPlanning.list_meal_plans(household.id)
        |> Enum.find(fn mp ->
          mp.start_date == start_date && mp.status in [:draft, :active]
        end)

      if existing do
        :ok
      else
        plan_name = "Week of #{Calendar.strftime(start_date, "%b %d")}"

        case MealPlanning.create_meal_plan(%{
               name: plan_name,
               start_date: start_date,
               end_date: end_date,
               household_id: household.id,
               ai_generated: true,
               status: :draft
             }) do
          {:ok, meal_plan} ->
            dates = Date.range(start_date, end_date) |> Enum.to_list()
            meal_types = ["breakfast", "lunch", "dinner"]
            shuffled = Enum.shuffle(recipes)
            recipe_cycle = Stream.cycle(shuffled)

            for {date, day_idx} <- Enum.with_index(dates),
                {meal_type, meal_idx} <- Enum.with_index(meal_types) do
              idx = day_idx * length(meal_types) + meal_idx
              recipe = Enum.at(recipe_cycle, idx)

              MealPlanning.create_item(%{
                date: date,
                meal_type: meal_type,
                title: recipe.title,
                servings: recipe.servings,
                meal_plan_id: meal_plan.id,
                recipe_id: recipe.id
              })
            end

            :ok

          {:error, _} ->
            {:error, "Failed to create meal plan"}
        end
      end
    end
  end

  defp today_for_household(household) do
    tz = household.timezone || "America/Los_Angeles"

    case DateTime.now(tz) do
      {:ok, dt} -> DateTime.to_date(dt)
      _ -> Date.utc_today()
    end
  end
end
