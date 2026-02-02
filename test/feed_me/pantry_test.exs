defmodule FeedMe.PantryTest do
  use FeedMe.DataCase

  alias FeedMe.Pantry
  alias FeedMe.Pantry.{Category, Item}
  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures
  alias FeedMe.PantryFixtures

  describe "categories" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "list_categories/1 returns all categories for a household", %{household: household} do
      category = PantryFixtures.category_fixture(household)
      categories = Pantry.list_categories(household.id)
      assert length(categories) == 1
      assert hd(categories).id == category.id
    end

    test "create_category/1 creates a category", %{household: household} do
      attrs = %{name: "Test Category", household_id: household.id}
      assert {:ok, %Category{} = category} = Pantry.create_category(attrs)
      assert category.name == "Test Category"
    end

    test "update_category/2 updates a category", %{household: household} do
      category = PantryFixtures.category_fixture(household)
      assert {:ok, %Category{} = updated} = Pantry.update_category(category, %{name: "Updated"})
      assert updated.name == "Updated"
    end

    test "delete_category/1 deletes a category", %{household: household} do
      category = PantryFixtures.category_fixture(household)
      assert {:ok, %Category{}} = Pantry.delete_category(category)
      assert Pantry.get_category(category.id) == nil
    end

    test "create_default_categories/1 creates default categories", %{household: household} do
      Pantry.create_default_categories(household.id)
      categories = Pantry.list_categories(household.id)
      assert length(categories) == 8
    end
  end

  describe "items" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "list_items/1 returns all items for a household", %{household: household} do
      item = PantryFixtures.item_fixture(household)
      items = Pantry.list_items(household.id)
      assert length(items) == 1
      assert hd(items).id == item.id
    end

    test "create_item/1 creates an item", %{household: household} do
      attrs = %{name: "Apples", quantity: Decimal.new("5"), household_id: household.id}
      assert {:ok, %Item{} = item} = Pantry.create_item(attrs)
      assert item.name == "Apples"
      assert Decimal.equal?(item.quantity, Decimal.new("5"))
    end

    test "update_item/2 updates an item", %{household: household} do
      item = PantryFixtures.item_fixture(household)
      assert {:ok, %Item{} = updated} = Pantry.update_item(item, %{name: "Updated Item"})
      assert updated.name == "Updated Item"
    end

    test "delete_item/1 deletes an item", %{household: household} do
      item = PantryFixtures.item_fixture(household)
      assert {:ok, %Item{}} = Pantry.delete_item(item)
      assert Pantry.get_item(item.id) == nil
    end

    test "adjust_quantity/4 adjusts item quantity and creates transaction", %{
      household: household,
      user: user
    } do
      item = PantryFixtures.item_fixture(household, %{quantity: Decimal.new("10")})

      {:ok, updated} = Pantry.adjust_quantity(item, Decimal.new("-3"), user, reason: "Test")

      assert Decimal.equal?(updated.quantity, Decimal.new("7"))

      transactions = Pantry.list_transactions_for_item(item.id)
      assert length(transactions) == 1
      assert hd(transactions).action == :adjust
      assert Decimal.equal?(hd(transactions).quantity_change, Decimal.new("-3"))
    end

    test "adjust_quantity/4 doesn't go negative", %{household: household, user: user} do
      item = PantryFixtures.item_fixture(household, %{quantity: Decimal.new("5")})

      {:ok, updated} = Pantry.adjust_quantity(item, Decimal.new("-10"), user)

      assert Decimal.equal?(updated.quantity, Decimal.new("0"))
    end

    test "add_to_item/4 adds to quantity", %{household: household, user: user} do
      item = PantryFixtures.item_fixture(household, %{quantity: Decimal.new("5")})

      {:ok, updated} = Pantry.add_to_item(item, 3, user)

      assert Decimal.equal?(updated.quantity, Decimal.new("8"))
    end

    test "remove_from_item/4 removes from quantity", %{household: household, user: user} do
      item = PantryFixtures.item_fixture(household, %{quantity: Decimal.new("10")})

      {:ok, updated} = Pantry.remove_from_item(item, 4, user)

      assert Decimal.equal?(updated.quantity, Decimal.new("6"))
    end

    test "items_needing_restock/1 returns items needing restock", %{household: household} do
      _normal_item = PantryFixtures.item_fixture(household, %{quantity: Decimal.new("10")})

      _restock_item =
        PantryFixtures.item_fixture(household, %{
          quantity: Decimal.new("2"),
          always_in_stock: true,
          restock_threshold: Decimal.new("5")
        })

      items = Pantry.items_needing_restock(household.id)
      assert length(items) == 1
    end

    test "search_items/2 finds items by name", %{household: household} do
      _item1 = PantryFixtures.item_fixture(household, %{name: "Apples"})
      _item2 = PantryFixtures.item_fixture(household, %{name: "Bananas"})
      _item3 = PantryFixtures.item_fixture(household, %{name: "Apple Juice"})

      results = Pantry.search_items(household.id, "Apple")
      assert length(results) == 2
    end
  end

  describe "item predicates" do
    test "needs_restock?/1 returns true when below threshold" do
      item = %Item{always_in_stock: true, quantity: Decimal.new("2"), restock_threshold: Decimal.new("5")}
      assert Item.needs_restock?(item)
    end

    test "needs_restock?/1 returns false when above threshold" do
      item = %Item{always_in_stock: true, quantity: Decimal.new("10"), restock_threshold: Decimal.new("5")}
      refute Item.needs_restock?(item)
    end

    test "needs_restock?/1 returns false when not always_in_stock" do
      item = %Item{always_in_stock: false, quantity: Decimal.new("0"), restock_threshold: Decimal.new("5")}
      refute Item.needs_restock?(item)
    end

    test "expired?/1 returns true for expired items" do
      item = %Item{expiration_date: Date.add(Date.utc_today(), -1)}
      assert Item.expired?(item)
    end

    test "expired?/1 returns false for non-expired items" do
      item = %Item{expiration_date: Date.add(Date.utc_today(), 7)}
      refute Item.expired?(item)
    end

    test "expiring_soon?/2 returns true for items expiring within range" do
      item = %Item{expiration_date: Date.add(Date.utc_today(), 3)}
      assert Item.expiring_soon?(item, 7)
    end

    test "expiring_soon?/2 returns false for items not expiring soon" do
      item = %Item{expiration_date: Date.add(Date.utc_today(), 30)}
      refute Item.expiring_soon?(item, 7)
    end
  end
end
