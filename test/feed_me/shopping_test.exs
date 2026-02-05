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

    test "add_from_pantry/4 adds a pantry item to shopping list", %{
      household: household,
      user: user
    } do
      pantry_item = PantryFixtures.item_fixture(household, %{name: "Apples", unit: "lbs"})
      list = Shopping.get_or_create_main_list(household.id)

      {:ok, item} = Shopping.add_from_pantry(list.id, pantry_item, Decimal.new("2"), user)

      assert item.name == "Apples"
      assert item.unit == "lbs"
      assert Decimal.equal?(item.quantity, Decimal.new("2"))
      assert item.pantry_item_id == pantry_item.id
    end

    test "add_restock_items_to_main_list/2 adds items needing restock", %{
      household: household,
      user: user
    } do
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

  describe "add_to_pantry feature" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "main list always has add_to_pantry: true", %{household: household} do
      list = Shopping.get_or_create_main_list(household.id)
      assert list.add_to_pantry == true
    end

    test "main list add_to_pantry cannot be set to false", %{household: household} do
      list = Shopping.get_or_create_main_list(household.id)
      {:ok, updated} = Shopping.update_list(list, %{add_to_pantry: false})
      assert updated.add_to_pantry == true
    end

    test "custom list add_to_pantry defaults to false", %{household: household} do
      {:ok, list} = Shopping.create_list(%{name: "Party List", household_id: household.id})
      assert list.add_to_pantry == false
    end

    test "custom list add_to_pantry can be toggled on", %{household: household} do
      {:ok, list} = Shopping.create_list(%{name: "Party List", household_id: household.id})
      assert list.add_to_pantry == false

      {:ok, updated} = Shopping.update_list(list, %{add_to_pantry: true})
      assert updated.add_to_pantry == true
    end

    test "checking item on add_to_pantry list queues item for pantry sync",
         %{household: household, user: user} do
      Application.put_env(:feed_me, FeedMe.Pantry.Sync, debounce_ms: 60_000, enabled: true)

      on_exit(fn ->
        Application.put_env(:feed_me, FeedMe.Pantry.Sync, debounce_ms: 0, enabled: false)
      end)

      pantry_item =
        PantryFixtures.item_fixture(household, %{name: "Milk", quantity: Decimal.new("2")})

      {:ok, list} =
        Shopping.create_list(%{
          name: "Grocery List",
          household_id: household.id,
          add_to_pantry: true
        })

      {:ok, item} = Shopping.add_from_pantry(list.id, pantry_item, Decimal.new("3"), user)

      {:ok, _checked} = Shopping.toggle_item_checked(item, user.id)

      # Item should be queued, NOT immediately added to pantry
      Process.sleep(10)
      assert FeedMe.Pantry.Sync.pending_count(household.id) == 1

      # Pantry quantity should be unchanged (async processing)
      updated_pantry_item = FeedMe.Pantry.get_item(pantry_item.id)
      assert Decimal.equal?(updated_pantry_item.quantity, Decimal.new("2"))
    end

    test "checking item on non-add_to_pantry list does NOT queue for sync",
         %{household: household, user: user} do
      Application.put_env(:feed_me, FeedMe.Pantry.Sync, debounce_ms: 60_000, enabled: true)

      on_exit(fn ->
        Application.put_env(:feed_me, FeedMe.Pantry.Sync, debounce_ms: 0, enabled: false)
      end)

      pantry_item =
        PantryFixtures.item_fixture(household, %{name: "Eggs", quantity: Decimal.new("6")})

      {:ok, list} =
        Shopping.create_list(%{
          name: "Party List",
          household_id: household.id,
          add_to_pantry: false
        })

      {:ok, item} = Shopping.add_from_pantry(list.id, pantry_item, Decimal.new("2"), user)

      {:ok, _checked} = Shopping.toggle_item_checked(item, user.id)

      Process.sleep(10)
      assert FeedMe.Pantry.Sync.pending_count(household.id) == 0

      updated_pantry_item = FeedMe.Pantry.get_item(pantry_item.id)
      assert Decimal.equal?(updated_pantry_item.quantity, Decimal.new("6"))
    end

    test "unchecking item dequeues it from sync",
         %{household: household, user: user} do
      Application.put_env(:feed_me, FeedMe.Pantry.Sync, debounce_ms: 60_000, enabled: true)

      on_exit(fn ->
        Application.put_env(:feed_me, FeedMe.Pantry.Sync, debounce_ms: 0, enabled: false)
      end)

      pantry_item =
        PantryFixtures.item_fixture(household, %{name: "Butter", quantity: Decimal.new("1")})

      {:ok, list} =
        Shopping.create_list(%{
          name: "Grocery List",
          household_id: household.id,
          add_to_pantry: true
        })

      {:ok, item} = Shopping.add_from_pantry(list.id, pantry_item, Decimal.new("2"), user)

      # Check the item (queues it)
      {:ok, checked} = Shopping.toggle_item_checked(item, user.id)
      assert checked.checked == true
      Process.sleep(10)
      assert FeedMe.Pantry.Sync.pending_count(household.id) == 1

      # Uncheck the item (dequeues it)
      {:ok, unchecked} = Shopping.toggle_item_checked(checked, user.id)
      assert unchecked.checked == false
      Process.sleep(10)
      assert FeedMe.Pantry.Sync.pending_count(household.id) == 0

      # Pantry should be unchanged
      pantry_after = FeedMe.Pantry.get_item(pantry_item.id)
      assert Decimal.equal?(pantry_after.quantity, Decimal.new("1"))
    end

    test "checking item without pantry_item_id and no matching pantry item does not error",
         %{household: household, user: user} do
      {:ok, list} =
        Shopping.create_list(%{
          name: "Grocery List",
          household_id: household.id,
          add_to_pantry: true
        })

      {:ok, item} =
        Shopping.create_item(%{
          name: "Random Item That Does Not Exist In Pantry",
          shopping_list_id: list.id,
          added_by_id: user.id
        })

      # Should not raise or error
      {:ok, checked} = Shopping.toggle_item_checked(item, user.id)
      assert checked.checked == true
    end
  end

  describe "pre-linking pantry items" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "create_item pre-links to pantry item by name", %{household: household, user: user} do
      pantry_item = PantryFixtures.item_fixture(household, %{name: "Milk"})
      {:ok, list} = Shopping.create_list(%{name: "Grocery List", household_id: household.id})

      {:ok, item} =
        Shopping.create_item(%{
          name: "Milk",
          shopping_list_id: list.id,
          added_by_id: user.id
        })

      assert item.pantry_item_id == pantry_item.id
    end

    test "create_item pre-links case-insensitively", %{household: household, user: user} do
      pantry_item = PantryFixtures.item_fixture(household, %{name: "Olive Oil"})
      {:ok, list} = Shopping.create_list(%{name: "Grocery List", household_id: household.id})

      {:ok, item} =
        Shopping.create_item(%{
          name: "olive oil",
          shopping_list_id: list.id,
          added_by_id: user.id
        })

      assert item.pantry_item_id == pantry_item.id
    end

    test "create_item does not overwrite existing pantry_item_id", %{
      household: household,
      user: user
    } do
      _pantry_item_a = PantryFixtures.item_fixture(household, %{name: "Milk"})
      pantry_item_b = PantryFixtures.item_fixture(household, %{name: "Whole Milk"})
      {:ok, list} = Shopping.create_list(%{name: "Grocery List", household_id: household.id})

      {:ok, item} =
        Shopping.create_item(%{
          name: "Milk",
          shopping_list_id: list.id,
          added_by_id: user.id,
          pantry_item_id: pantry_item_b.id
        })

      # Should keep the explicitly set pantry_item_id
      assert item.pantry_item_id == pantry_item_b.id
    end

    test "create_item with no matching pantry item leaves pantry_item_id nil",
         %{household: household, user: user} do
      {:ok, list} = Shopping.create_list(%{name: "Grocery List", household_id: household.id})

      {:ok, item} =
        Shopping.create_item(%{
          name: "Something Not In Pantry",
          shopping_list_id: list.id,
          added_by_id: user.id
        })

      assert item.pantry_item_id == nil
    end
  end
end
