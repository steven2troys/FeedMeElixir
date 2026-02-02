defmodule FeedMe.ShoppingTest do
  use FeedMe.DataCase

  alias FeedMe.Shopping
  alias FeedMe.Shopping.{List, Item}
  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures
  alias FeedMe.PantryFixtures
  alias FeedMe.ShoppingFixtures

  describe "lists" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "list_shopping_lists/1 returns all lists for a household", %{household: household} do
      list = ShoppingFixtures.shopping_list_fixture(household)
      lists = Shopping.list_shopping_lists(household.id)
      assert length(lists) == 1
      assert hd(lists).id == list.id
    end

    test "get_or_create_main_list/1 creates main list if none exists", %{household: household} do
      list = Shopping.get_or_create_main_list(household.id)
      assert list.is_main == true
      assert list.name == "Shopping List"
    end

    test "get_or_create_main_list/1 returns existing main list", %{household: household} do
      first = Shopping.get_or_create_main_list(household.id)
      second = Shopping.get_or_create_main_list(household.id)
      assert first.id == second.id
    end

    test "create_list/1 creates a list", %{household: household} do
      attrs = %{name: "Weekly Groceries", household_id: household.id}
      assert {:ok, %List{} = list} = Shopping.create_list(attrs)
      assert list.name == "Weekly Groceries"
      assert list.status == :active
    end

    test "update_list/2 updates a list", %{household: household} do
      list = ShoppingFixtures.shopping_list_fixture(household)
      assert {:ok, %List{} = updated} = Shopping.update_list(list, %{name: "Updated"})
      assert updated.name == "Updated"
    end

    test "delete_list/1 deletes a list", %{household: household} do
      list = ShoppingFixtures.shopping_list_fixture(household)
      assert {:ok, %List{}} = Shopping.delete_list(list)
      assert Shopping.get_list(list.id) == nil
    end

    test "complete_list/1 marks list as completed", %{household: household} do
      list = ShoppingFixtures.shopping_list_fixture(household)
      assert {:ok, %List{} = completed} = Shopping.complete_list(list)
      assert completed.status == :completed
    end
  end

  describe "items" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      list = ShoppingFixtures.shopping_list_fixture(household)
      %{user: user, household: household, list: list}
    end

    test "list_items/1 returns all items in a list", %{list: list} do
      item = ShoppingFixtures.shopping_item_fixture(list)
      items = Shopping.list_items(list.id)
      assert length(items) == 1
      assert hd(items).id == item.id
    end

    test "create_item/1 creates an item", %{list: list, user: user} do
      attrs = %{name: "Milk", shopping_list_id: list.id, added_by_id: user.id}
      assert {:ok, %Item{} = item} = Shopping.create_item(attrs)
      assert item.name == "Milk"
      assert item.checked == false
    end

    test "update_item/2 updates an item", %{list: list} do
      item = ShoppingFixtures.shopping_item_fixture(list)
      assert {:ok, %Item{} = updated} = Shopping.update_item(item, %{name: "Updated"})
      assert updated.name == "Updated"
    end

    test "delete_item/1 deletes an item", %{list: list} do
      item = ShoppingFixtures.shopping_item_fixture(list)
      assert {:ok, %Item{}} = Shopping.delete_item(item)
      assert Shopping.get_item(item.id) == nil
    end

    test "toggle_item_checked/2 toggles checked status", %{list: list, user: user} do
      item = ShoppingFixtures.shopping_item_fixture(list)
      assert item.checked == false

      {:ok, checked} = Shopping.toggle_item_checked(item, user.id)
      assert checked.checked == true
      assert checked.checked_by_id == user.id

      {:ok, unchecked} = Shopping.toggle_item_checked(checked, user.id)
      assert unchecked.checked == false
      assert unchecked.checked_by_id == nil
    end

    test "list_unchecked_items/1 returns only unchecked items", %{list: list, user: user} do
      item1 = ShoppingFixtures.shopping_item_fixture(list)
      item2 = ShoppingFixtures.shopping_item_fixture(list)
      Shopping.toggle_item_checked(item1, user.id)

      unchecked = Shopping.list_unchecked_items(list.id)
      assert length(unchecked) == 1
      assert hd(unchecked).id == item2.id
    end

    test "clear_checked_items/1 removes checked items", %{list: list, user: user} do
      item1 = ShoppingFixtures.shopping_item_fixture(list)
      _item2 = ShoppingFixtures.shopping_item_fixture(list)
      Shopping.toggle_item_checked(item1, user.id)

      {:ok, count} = Shopping.clear_checked_items(list)
      assert count == 1

      items = Shopping.list_items(list.id)
      assert length(items) == 1
    end
  end

  describe "pantry integration" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "add_from_pantry/4 adds a pantry item to shopping list", %{household: household, user: user} do
      pantry_item = PantryFixtures.item_fixture(household, %{name: "Apples", unit: "lbs"})
      list = Shopping.get_or_create_main_list(household.id)

      {:ok, item} = Shopping.add_from_pantry(list.id, pantry_item, Decimal.new("2"), user)

      assert item.name == "Apples"
      assert item.unit == "lbs"
      assert Decimal.equal?(item.quantity, Decimal.new("2"))
      assert item.pantry_item_id == pantry_item.id
    end

    test "add_restock_items_to_main_list/2 adds items needing restock", %{household: household, user: user} do
      _normal_item = PantryFixtures.item_fixture(household, %{name: "Normal"})

      _restock_item =
        PantryFixtures.item_fixture(household, %{
          name: "Low Item",
          quantity: Decimal.new("1"),
          always_in_stock: true,
          restock_threshold: Decimal.new("5")
        })

      list = Shopping.add_restock_items_to_main_list(household.id, user)
      items = Shopping.list_items(list.id)

      assert length(items) == 1
      assert hd(items).name == "Low Item"
    end
  end
end
