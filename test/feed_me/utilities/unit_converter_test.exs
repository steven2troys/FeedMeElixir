defmodule FeedMe.Utilities.UnitConverterTest do
  use ExUnit.Case, async: true

  alias FeedMe.Utilities.UnitConverter

  describe "convert/3" do
    test "converts cups to ml" do
      assert {:ok, 473.176} = UnitConverter.convert(2, "cups", "ml")
    end

    test "converts tbsp to tsp" do
      {:ok, result} = UnitConverter.convert(1, "tbsp", "tsp")
      assert_in_delta result, 3.0, 0.1
    end

    test "converts oz to lb" do
      {:ok, result} = UnitConverter.convert(16, "oz", "lb")
      assert_in_delta result, 1.0, 0.01
    end

    test "converts kg to g" do
      assert {:ok, 1000.0} = UnitConverter.convert(1, "kg", "g")
    end

    test "handles same unit conversion" do
      {:ok, result} = UnitConverter.convert(5, "cups", "cups")
      assert result == 5.0 or result == 5
    end

    test "returns error for incompatible units" do
      assert {:error, :incompatible_units} = UnitConverter.convert(1, "cups", "oz")
    end

    test "normalizes unit case" do
      assert {:ok, _} = UnitConverter.convert(1, "CUPS", "ML")
    end

    test "handles plural and singular forms" do
      {:ok, result1} = UnitConverter.convert(1, "cup", "ml")
      {:ok, result2} = UnitConverter.convert(1, "cups", "ml")
      assert result1 == result2
    end
  end

  describe "convert!/3" do
    test "returns value directly on success" do
      assert 473.176 = UnitConverter.convert!(2, "cups", "ml")
    end

    test "raises on error" do
      assert_raise RuntimeError, fn ->
        UnitConverter.convert!(1, "cups", "oz")
      end
    end
  end

  describe "volume_unit?/1" do
    test "returns true for volume units" do
      assert UnitConverter.volume_unit?("ml")
      assert UnitConverter.volume_unit?("cups")
      assert UnitConverter.volume_unit?("tsp")
    end

    test "returns false for weight units" do
      refute UnitConverter.volume_unit?("oz")
      refute UnitConverter.volume_unit?("kg")
    end
  end

  describe "weight_unit?/1" do
    test "returns true for weight units" do
      assert UnitConverter.weight_unit?("g")
      assert UnitConverter.weight_unit?("oz")
      assert UnitConverter.weight_unit?("lb")
    end

    test "returns false for volume units" do
      refute UnitConverter.weight_unit?("ml")
      refute UnitConverter.weight_unit?("cups")
    end
  end

  describe "volume_units/0" do
    test "returns list of volume units" do
      units = UnitConverter.volume_units()
      assert "ml" in units
      assert "cup" in units
      assert "tbsp" in units
    end
  end

  describe "weight_units/0" do
    test "returns list of weight units" do
      units = UnitConverter.weight_units()
      assert "g" in units
      assert "oz" in units
      assert "lb" in units
    end
  end

  describe "format/2" do
    test "formats integer values" do
      assert "5 cups" = UnitConverter.format(5, "cups")
    end

    test "formats decimal values" do
      assert "2.5 cups" = UnitConverter.format(2.5, "cups")
    end

    test "formats small values with precision" do
      assert "0.25 tsp" = UnitConverter.format(0.25, "tsp")
    end
  end

  describe "suggest_unit/2" do
    test "suggests larger units for volume" do
      {:ok, value, unit} = UnitConverter.suggest_unit(1000, "ml")
      assert unit == "qt"
      assert_in_delta value, 1.06, 0.1
    end

    test "suggests larger units for weight" do
      {:ok, value, unit} = UnitConverter.suggest_unit(1000, "g")
      assert unit == "lb"
      assert_in_delta value, 2.2, 0.1
    end
  end
end
