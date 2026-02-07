defmodule FeedMe.ShoppingFixtures do
  @moduledoc """
  Test helpers for creating shopping entities.
  """

  alias FeedMe.Shopping

  def unique_list_name, do: "List #{System.unique_integer()}"
  def unique_item_name, do: "Item #{System.unique_integer()}"

  @doc """
  Generate a shopping list.
  """
  def shopping_list_fixture(household, attrs \\ %{}) do
    {:ok, list} =
      attrs
      |> Enum.into(%{
        name: unique_list_name(),
        household_id: household.id
      })
      |> Shopping.create_list()

    FeedMe.Repo.preload(list, :shares)
  end

  @doc """
  Generate a shopping list item.
  """
  def shopping_item_fixture(shopping_list, attrs \\ %{}) do
    {:ok, item} =
      attrs
      |> Enum.into(%{
        name: unique_item_name(),
        shopping_list_id: shopping_list.id
      })
      |> Shopping.create_item()

    item
  end
end
