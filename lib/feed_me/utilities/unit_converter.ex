defmodule FeedMe.Utilities.UnitConverter do
  @moduledoc """
  Unit conversion utility for cooking measurements.
  """

  # Volume conversions (to milliliters)
  @volume_to_ml %{
    "ml" => 1,
    "milliliter" => 1,
    "milliliters" => 1,
    "l" => 1000,
    "liter" => 1000,
    "liters" => 1000,
    "tsp" => 4.929,
    "teaspoon" => 4.929,
    "teaspoons" => 4.929,
    "tbsp" => 14.787,
    "tablespoon" => 14.787,
    "tablespoons" => 14.787,
    "fl oz" => 29.574,
    "fluid ounce" => 29.574,
    "fluid ounces" => 29.574,
    "cup" => 236.588,
    "cups" => 236.588,
    "pt" => 473.176,
    "pint" => 473.176,
    "pints" => 473.176,
    "qt" => 946.353,
    "quart" => 946.353,
    "quarts" => 946.353,
    "gal" => 3785.41,
    "gallon" => 3785.41,
    "gallons" => 3785.41
  }

  # Weight conversions (to grams)
  @weight_to_g %{
    "g" => 1,
    "gram" => 1,
    "grams" => 1,
    "kg" => 1000,
    "kilogram" => 1000,
    "kilograms" => 1000,
    "oz" => 28.3495,
    "ounce" => 28.3495,
    "ounces" => 28.3495,
    "lb" => 453.592,
    "lbs" => 453.592,
    "pound" => 453.592,
    "pounds" => 453.592
  }

  @doc """
  Converts a value from one unit to another.

  ## Examples

      iex> UnitConverter.convert(2, "cups", "ml")
      {:ok, 473.176}

      iex> UnitConverter.convert(16, "oz", "lb")
      {:ok, 1.0}

  """
  def convert(value, from_unit, to_unit) do
    from_unit = normalize_unit(from_unit)
    to_unit = normalize_unit(to_unit)

    cond do
      volume_unit?(from_unit) and volume_unit?(to_unit) ->
        convert_volume(value, from_unit, to_unit)

      weight_unit?(from_unit) and weight_unit?(to_unit) ->
        convert_weight(value, from_unit, to_unit)

      from_unit == to_unit ->
        {:ok, value}

      true ->
        {:error, :incompatible_units}
    end
  end

  @doc """
  Converts a value and returns the result directly or raises on error.
  """
  def convert!(value, from_unit, to_unit) do
    case convert(value, from_unit, to_unit) do
      {:ok, result} -> result
      {:error, reason} -> raise "Conversion failed: #{reason}"
    end
  end

  @doc """
  Returns all available volume units.
  """
  def volume_units do
    ["ml", "l", "tsp", "tbsp", "fl oz", "cup", "pt", "qt", "gal"]
  end

  @doc """
  Returns all available weight units.
  """
  def weight_units do
    ["g", "kg", "oz", "lb"]
  end

  @doc """
  Returns all available units.
  """
  def all_units do
    volume_units() ++ weight_units()
  end

  @doc """
  Checks if a unit is a volume unit.
  """
  def volume_unit?(unit) do
    Map.has_key?(@volume_to_ml, normalize_unit(unit))
  end

  @doc """
  Checks if a unit is a weight unit.
  """
  def weight_unit?(unit) do
    Map.has_key?(@weight_to_g, normalize_unit(unit))
  end

  @doc """
  Formats a value with its unit, using appropriate precision.
  """
  def format(value, unit) when is_number(value) do
    formatted =
      cond do
        value == trunc(value) -> Integer.to_string(trunc(value))
        value < 1 -> :erlang.float_to_binary(value * 1.0, decimals: 2)
        value < 10 -> :erlang.float_to_binary(value * 1.0, decimals: 1)
        true -> :erlang.float_to_binary(value * 1.0, decimals: 0)
      end

    "#{formatted} #{unit}"
  end

  def format(%Decimal{} = value, unit) do
    format(Decimal.to_float(value), unit)
  end

  @doc """
  Suggests the best unit for display based on the value.
  For example, 1000ml might be better displayed as 1L.
  """
  def suggest_unit(value, current_unit) do
    current_unit = normalize_unit(current_unit)

    cond do
      volume_unit?(current_unit) ->
        suggest_volume_unit(value, current_unit)

      weight_unit?(current_unit) ->
        suggest_weight_unit(value, current_unit)

      true ->
        {:ok, value, current_unit}
    end
  end

  # Private functions

  defp normalize_unit(unit) when is_binary(unit) do
    unit
    |> String.downcase()
    |> String.trim()
  end

  defp normalize_unit(unit), do: to_string(unit) |> normalize_unit()

  defp convert_volume(value, from, to) do
    ml_value = value * @volume_to_ml[from]
    result = ml_value / @volume_to_ml[to]
    {:ok, Float.round(result, 3)}
  end

  defp convert_weight(value, from, to) do
    g_value = value * @weight_to_g[from]
    result = g_value / @weight_to_g[to]
    {:ok, Float.round(result, 3)}
  end

  defp suggest_volume_unit(value, current_unit) do
    ml_value = value * @volume_to_ml[current_unit]

    {best_unit, best_value} =
      cond do
        ml_value >= 3785.41 -> {"gal", ml_value / 3785.41}
        ml_value >= 946.353 -> {"qt", ml_value / 946.353}
        ml_value >= 473.176 -> {"pt", ml_value / 473.176}
        ml_value >= 236.588 -> {"cup", ml_value / 236.588}
        ml_value >= 14.787 -> {"tbsp", ml_value / 14.787}
        ml_value >= 4.929 -> {"tsp", ml_value / 4.929}
        true -> {"ml", ml_value}
      end

    {:ok, Float.round(best_value, 2), best_unit}
  end

  defp suggest_weight_unit(value, current_unit) do
    g_value = value * @weight_to_g[current_unit]

    {best_unit, best_value} =
      cond do
        g_value >= 453.592 -> {"lb", g_value / 453.592}
        g_value >= 28.3495 -> {"oz", g_value / 28.3495}
        g_value >= 1000 -> {"kg", g_value / 1000}
        true -> {"g", g_value}
      end

    {:ok, Float.round(best_value, 2), best_unit}
  end
end
