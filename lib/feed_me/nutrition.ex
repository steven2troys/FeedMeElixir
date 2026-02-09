defmodule FeedMe.Nutrition do
  @moduledoc """
  Helper functions for nutritional information calculations and display.
  """

  alias FeedMe.AI.{ApiKey, OpenRouter}
  alias FeedMe.Nutrition.Info
  alias FeedMe.Pantry
  alias FeedMe.Recipes

  @doc """
  Sums nutrition across a recipe's ingredients.

  Returns an Info struct with totals, or nil if no ingredients have nutrition.
  """
  def recipe_total(%{ingredients: ingredients}) when is_list(ingredients) do
    nutritions =
      ingredients
      |> Enum.map(& &1.nutrition)
      |> Enum.reject(&is_nil/1)

    case nutritions do
      [] -> nil
      nutritions -> sum_nutritions(nutritions)
    end
  end

  def recipe_total(_), do: nil

  @doc """
  Returns per-serving nutrition for a recipe.

  Divides the total by `recipe.servings` (defaults to 1).
  """
  def recipe_per_serving(%{servings: servings} = recipe) do
    case recipe_total(recipe) do
      nil ->
        nil

      total ->
        divisor = Decimal.new(servings || 1)
        divide_nutrition(total, divisor)
    end
  end

  @doc """
  Filters a nutrition struct by display tier.

  - "none" -> nil
  - "basic" -> only calories, protein, carbs, fat
  - "detailed" -> everything
  """
  def for_display(nil, _tier), do: nil
  def for_display(_nutrition, "none"), do: nil

  def for_display(%Info{} = nutrition, "basic") do
    Map.take(nutrition, [:calories, :protein_g, :carbs_g, :fat_g, :serving_size, :source])
  end

  def for_display(%Info{} = nutrition, "detailed"), do: nutrition
  def for_display(%Info{} = nutrition, _), do: nutrition

  @doc """
  Backfills nutrition data for all pantry items in a household that don't have it.

  Makes a single AI call with all item names and parses the JSON response.
  Returns `{:ok, count}` or `{:error, reason}`.
  """
  def backfill_pantry_items(household_id) do
    items =
      Pantry.list_items(household_id)
      |> Enum.filter(fn item -> is_nil(item.nutrition) end)

    if items == [] do
      {:ok, 0}
    else
      case estimate_batch(household_id, items, :pantry) do
        {:ok, count} -> {:ok, count}
        error -> error
      end
    end
  end

  @doc """
  Backfills nutrition data for all recipe ingredients in a household.
  """
  def backfill_recipe_ingredients(household_id) do
    recipes = Recipes.list_recipes(household_id)

    ingredients =
      recipes
      |> Enum.flat_map(fn r ->
        r = FeedMe.Repo.preload(r, :ingredients)
        r.ingredients
      end)
      |> Enum.filter(fn ing -> is_nil(ing.nutrition) end)

    if ingredients == [] do
      {:ok, 0}
    else
      case estimate_batch(household_id, ingredients, :ingredient) do
        {:ok, count} -> {:ok, count}
        error -> error
      end
    end
  end

  defp estimate_batch(household_id, items, type) do
    case FeedMe.AI.get_api_key(household_id) do
      nil ->
        {:error, :no_api_key}

      api_key_record ->
        decrypted_key = ApiKey.decrypt_key(api_key_record)
        household = FeedMe.Households.get_household(household_id)
        model = (household && household.selected_model) || FeedMe.AI.default_model()

        # Process in batches of 20
        items
        |> Enum.chunk_every(20)
        |> Enum.reduce({:ok, 0}, fn batch, {:ok, total} ->
          case estimate_and_save_batch(decrypted_key, model, batch, type) do
            {:ok, count} -> {:ok, total + count}
            error -> error
          end
        end)
    end
  end

  defp estimate_and_save_batch(api_key, model, items, type) do
    item_list =
      items
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        qty_str =
          if item.quantity && item.unit do
            " (#{Decimal.to_string(item.quantity)} #{item.unit})"
          else
            ""
          end

        "#{idx + 1}. #{item.name}#{qty_str}"
      end)
      |> Enum.join("\n")

    messages = [
      %{
        role: :system,
        content: """
        You are a nutrition database. Return ONLY a JSON array with nutritional estimates.
        No explanation, no markdown, just the JSON array.
        Each element must have: index (1-based), calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, serving_size.
        Use typical values per standard serving. All numbers should be reasonable estimates.
        """
      },
      %{
        role: :user,
        content: "Estimate nutrition for these items:\n#{item_list}"
      }
    ]

    case OpenRouter.chat(api_key, messages, model: model) do
      {:ok, response} ->
        parse_and_save_batch(response.content, items, type)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_and_save_batch(content, items, type) do
    # Extract JSON from response (may have markdown code fences)
    json_str =
      content
      |> String.replace(~r/```json\s*/, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(json_str) do
      {:ok, estimates} when is_list(estimates) ->
        count =
          Enum.reduce(estimates, 0, fn estimate, acc ->
            index = (estimate["index"] || 0) - 1

            case Enum.at(items, index) do
              nil ->
                acc

              item ->
                nutrition_attrs = %{
                  calories: decimal_or_nil(estimate["calories"]),
                  protein_g: decimal_or_nil(estimate["protein_g"]),
                  carbs_g: decimal_or_nil(estimate["carbs_g"]),
                  fat_g: decimal_or_nil(estimate["fat_g"]),
                  fiber_g: decimal_or_nil(estimate["fiber_g"]),
                  sugar_g: decimal_or_nil(estimate["sugar_g"]),
                  sodium_mg: decimal_or_nil(estimate["sodium_mg"]),
                  serving_size: estimate["serving_size"],
                  source: "ai_estimated"
                }

                result =
                  case type do
                    :pantry -> Pantry.update_item_nutrition(item, nutrition_attrs)
                    :ingredient -> Recipes.update_ingredient_nutrition(item, nutrition_attrs)
                  end

                case result do
                  {:ok, _} -> acc + 1
                  _ -> acc
                end
            end
          end)

        {:ok, count}

      _ ->
        {:error, :invalid_json}
    end
  end

  defp decimal_or_nil(nil), do: nil
  defp decimal_or_nil(val) when is_number(val), do: Decimal.new("#{val}")
  defp decimal_or_nil(_), do: nil

  defp sum_nutritions(nutritions) do
    fields = Info.all_nutrient_fields()

    summed =
      Enum.reduce(nutritions, %{}, fn nutrition, acc ->
        Enum.reduce(fields, acc, fn field, acc2 ->
          val = Map.get(nutrition, field)

          if val do
            Map.update(acc2, field, val, &Decimal.add(&1, val))
          else
            acc2
          end
        end)
      end)

    # Preserve metadata from first item
    first = List.first(nutritions)

    struct!(Info, Map.merge(summed, %{serving_size: first.serving_size, source: first.source}))
  end

  defp divide_nutrition(%Info{} = nutrition, divisor) do
    fields = Info.all_nutrient_fields()

    divided =
      Enum.reduce(fields, %{}, fn field, acc ->
        val = Map.get(nutrition, field)

        if val do
          Map.put(acc, field, Decimal.div(val, divisor) |> Decimal.round(1))
        else
          acc
        end
      end)

    struct!(
      Info,
      Map.merge(divided, %{serving_size: nutrition.serving_size, source: nutrition.source})
    )
  end
end
