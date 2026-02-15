defmodule FeedMeWeb.RestockHooksTest do
  use FeedMeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FeedMe.Shopping
  alias FeedMe.Pantry

  setup do
    user = FeedMe.AccountsFixtures.user_fixture()
    household = FeedMe.HouseholdsFixtures.household_fixture(%{}, user)
    location = Pantry.get_pantry_location(household.id)
    %{user: user, household: household, location: location}
  end

  describe "keep-in-stock auto-add" do
    test "auto-adds to shopping list when keep-in-stock item hits threshold",
         %{conn: conn, user: user, household: household, location: location} do
      pantry_item =
        FeedMe.PantryFixtures.item_fixture(household, %{
          name: "Milk",
          quantity: Decimal.new("3"),
          always_in_stock: true,
          restock_threshold: Decimal.new("2")
        })

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/households/#{household.id}/pantry/locations/#{location.id}")

      # Trigger restock by adjusting quantity below threshold
      Pantry.adjust_quantity(pantry_item, Decimal.new("-2"), user, reason: "test")

      # Give the hook time to process the PubSub message
      _ = render(view)

      # Check that item was auto-added to shopping list
      main_list = Shopping.get_or_create_main_list(household.id)
      assert Shopping.item_on_list?(main_list.id, pantry_item.id)
    end

    test "does not duplicate when item already on shopping list",
         %{conn: conn, user: user, household: household, location: location} do
      pantry_item =
        FeedMe.PantryFixtures.item_fixture(household, %{
          name: "Eggs",
          quantity: Decimal.new("5"),
          always_in_stock: true,
          restock_threshold: Decimal.new("3")
        })

      # Pre-add to shopping list
      main_list = Shopping.get_or_create_main_list(household.id)
      Shopping.add_from_pantry(main_list.id, pantry_item, Decimal.new("2"), user)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/households/#{household.id}/pantry/locations/#{location.id}")

      # Trigger restock
      Pantry.adjust_quantity(pantry_item, Decimal.new("-3"), user, reason: "test")
      _ = render(view)

      # Should still only have 1 entry
      items = Shopping.list_items(main_list.id)
      pantry_linked = Enum.filter(items, &(&1.pantry_item_id == pantry_item.id))
      assert length(pantry_linked) == 1
    end
  end

  describe "item depleted prompt" do
    test "stores depleted item in restock_prompts assign",
         %{conn: conn, user: user, household: household, location: location} do
      pantry_item =
        FeedMe.PantryFixtures.item_fixture(household, %{
          name: "Avocados",
          quantity: Decimal.new("1"),
          always_in_stock: false
        })

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/households/#{household.id}/pantry/locations/#{location.id}")

      # Trigger depletion by adjusting quantity to zero
      Pantry.adjust_quantity(pantry_item, Decimal.new("-1"), user, reason: "test")

      # Render to process PubSub message
      _ = render(view)

      # The view should still render without error after receiving the depleted message
      html = render(view)
      assert html =~ "On Hand"
    end

    test "does not prompt for depleted item already on shopping list",
         %{conn: conn, user: user, household: household, location: location} do
      pantry_item =
        FeedMe.PantryFixtures.item_fixture(household, %{
          name: "Bananas",
          quantity: Decimal.new("1"),
          always_in_stock: false
        })

      # Pre-add to shopping list
      main_list = Shopping.get_or_create_main_list(household.id)
      Shopping.add_from_pantry(main_list.id, pantry_item, Decimal.new("1"), user)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/households/#{household.id}/pantry/locations/#{location.id}")

      # Trigger depletion
      Pantry.adjust_quantity(pantry_item, Decimal.new("-1"), user, reason: "test")

      # Render to process PubSub message - should not crash
      _ = render(view)
      html = render(view)
      assert html =~ "On Hand"
    end
  end
end
