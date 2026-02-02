defmodule FeedMe.PantryFixtures do
  @moduledoc """
  Test helpers for creating pantry entities.
  """

  alias FeedMe.Pantry

  def unique_item_name, do: "Item #{System.unique_integer()}"
  def unique_category_name, do: "Category #{System.unique_integer()}"

  @doc """
  Generate a category.
  """
  def category_fixture(household, attrs \\ %{}) do
    {:ok, category} =
      attrs
      |> Enum.into(%{
        name: unique_category_name(),
        household_id: household.id
      })
      |> Pantry.create_category()

    category
  end

  @doc """
  Generate an item.
  """
  def item_fixture(household, attrs \\ %{}) do
    {:ok, item} =
      attrs
      |> Enum.into(%{
        name: unique_item_name(),
        quantity: Decimal.new("10"),
        household_id: household.id
      })
      |> Pantry.create_item()

    item
  end
end
