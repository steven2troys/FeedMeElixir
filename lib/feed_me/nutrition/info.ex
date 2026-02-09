defimpl Jason.Encoder, for: Decimal do
  def encode(decimal, _opts) do
    [Decimal.to_string(decimal, :normal)]
  end
end

defmodule FeedMe.Nutrition.Info do
  @moduledoc """
  Embedded schema for nutritional information.

  Stored as JSONB in pantry_items and recipe_ingredients.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @basic_fields [:calories, :protein_g, :carbs_g, :fat_g]
  @detailed_fields [
    :saturated_fat_g,
    :fiber_g,
    :sugar_g,
    :sodium_mg,
    :cholesterol_mg
  ]
  @micronutrient_fields [
    :vitamin_a_mcg,
    :vitamin_c_mg,
    :vitamin_d_mcg,
    :vitamin_k_mcg,
    :calcium_mg,
    :iron_mg,
    :potassium_mg
  ]
  @all_nutrient_fields @basic_fields ++ @detailed_fields ++ @micronutrient_fields

  def basic_fields, do: @basic_fields
  def all_nutrient_fields, do: @all_nutrient_fields

  @primary_key false
  embedded_schema do
    # Basic macros
    field :calories, :decimal
    field :protein_g, :decimal
    field :carbs_g, :decimal
    field :fat_g, :decimal

    # Detailed
    field :saturated_fat_g, :decimal
    field :fiber_g, :decimal
    field :sugar_g, :decimal
    field :sodium_mg, :decimal
    field :cholesterol_mg, :decimal

    # Micronutrients
    field :vitamin_a_mcg, :decimal
    field :vitamin_c_mg, :decimal
    field :vitamin_d_mcg, :decimal
    field :vitamin_k_mcg, :decimal
    field :calcium_mg, :decimal
    field :iron_mg, :decimal
    field :potassium_mg, :decimal

    # Metadata
    field :serving_size, :string
    field :source, :string
  end

  @doc false
  def changeset(info, attrs) do
    info
    |> cast(attrs, @all_nutrient_fields ++ [:serving_size, :source])
    |> validate_non_negative(@all_nutrient_fields)
  end

  defp validate_non_negative(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      validate_number(cs, field, greater_than_or_equal_to: 0)
    end)
  end
end
