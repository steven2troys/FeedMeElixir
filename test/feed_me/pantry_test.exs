defmodule FeedMe.PantryTest do
  use FeedMe.DataCase

  alias FeedMe.Pantry
  alias FeedMe.Pantry.{Category, Item}
  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures
  alias FeedMe.PantryFixtures

  describe "storage_locations" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "create_household auto-creates default locations", %{household: household} do
      locations = Pantry.list_storage_locations(household.id)
      assert length(locations) == 2
      assert Enum.any?(locations, &(&1.name == "On Hand" and &1.is_default))
      assert Enum.any?(locations, &(&1.name == "Pantry" and not &1.is_default))
    end

    test "get_default_storage_location/1 returns the On Hand location", %{household: household} do
      default = Pantry.get_default_storage_location(household.id)
      assert default.name == "On Hand"
      assert default.is_default
    end

    test "get_pantry_location/1 returns the Pantry location", %{household: household} do
      pantry = Pantry.get_pantry_location(household.id)
      assert pantry.name == "Pantry"
      refute pantry.is_default
    end

    test "create_storage_location/2 with template creates categories", %{household: household} do
      {:ok, location} =
        Pantry.create_storage_location(
          %{name: "Garage", icon: "hero-wrench-screwdriver", household_id: household.id},
          template: :garage
        )

      categories = Pantry.list_categories(location.id)
      assert length(categories) == 6
      assert Enum.any?(categories, &(&1.name == "Tools"))
    end

    test "delete_storage_location/1 moves items to default", %{household: household} do
      {:ok, garage} =
        Pantry.create_storage_location(%{
          name: "Garage",
          icon: "hero-wrench-screwdriver",
          household_id: household.id
        })

      {:ok, item} =
        Pantry.create_item(%{
          name: "Hammer",
          quantity: Decimal.new("1"),
          household_id: household.id,
          storage_location_id: garage.id
        })

      {:ok, _} = Pantry.delete_storage_location(garage)

      moved_item = Pantry.get_item(item.id)
      default = Pantry.get_default_storage_location(household.id)
      assert moved_item.storage_location_id == default.id
      assert is_nil(moved_item.category_id)
    end

    test "cannot delete default location", %{household: household} do
      default = Pantry.get_default_storage_location(household.id)
      assert {:error, :cannot_delete_default} = Pantry.delete_storage_location(default)
    end
  end

  describe "categories" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      location = PantryFixtures.storage_location_fixture(household)
      %{user: user, household: household, location: location}
    end

    test "list_categories/1 returns all categories for a location", %{
      household: household,
      location: location
    } do
      # Pantry location auto-gets 8 default categories from create_default_locations
      initial_count = length(Pantry.list_categories(location.id))

      category = PantryFixtures.category_fixture(household)
      categories = Pantry.list_categories(location.id)
      assert length(categories) == initial_count + 1
      assert Enum.any?(categories, &(&1.id == category.id))
    end

    test "create_category/1 creates a category", %{household: household, location: location} do
      attrs = %{
        name: "Test Category",
        household_id: household.id,
        storage_location_id: location.id
      }

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

    test "create_default_categories/3 creates default categories", %{household: household} do
      {:ok, new_loc} =
        Pantry.create_storage_location(%{
          name: "Test Loc",
          household_id: household.id
        })

      Pantry.create_default_categories(new_loc.id, household.id)
      categories = Pantry.list_categories(new_loc.id)
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

    test "list_items with storage_location_id filter", %{household: household} do
      location = PantryFixtures.storage_location_fixture(household)
      _item = PantryFixtures.item_fixture(household)

      {:ok, other_loc} =
        Pantry.create_storage_location(%{name: "Other", household_id: household.id})

      {:ok, _other_item} =
        Pantry.create_item(%{
          name: "Other Item",
          quantity: Decimal.new("1"),
          household_id: household.id,
          storage_location_id: other_loc.id
        })

      items = Pantry.list_items(household.id, storage_location_id: location.id)
      assert length(items) == 1

      items = Pantry.list_items(household.id, storage_location_id: other_loc.id)
      assert length(items) == 1
    end

    test "create_item/1 creates an item", %{household: household} do
      location = PantryFixtures.storage_location_fixture(household)

      attrs = %{
        name: "Apples",
        quantity: Decimal.new("5"),
        household_id: household.id,
        storage_location_id: location.id
      }

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

    test "move_item_to_location/2 moves item and clears category", %{household: household} do
      category = PantryFixtures.category_fixture(household)
      item = PantryFixtures.item_fixture(household, %{category_id: category.id})

      {:ok, other_loc} =
        Pantry.create_storage_location(%{name: "Other", household_id: household.id})

      {:ok, moved} = Pantry.move_item_to_location(item, other_loc.id)
      assert moved.storage_location_id == other_loc.id
      assert is_nil(moved.category_id)
    end
  end

  describe "item predicates" do
    test "needs_restock?/1 returns true when below threshold" do
      item = %Item{
        always_in_stock: true,
        quantity: Decimal.new("2"),
        restock_threshold: Decimal.new("5")
      }

      assert Item.needs_restock?(item)
    end

    test "needs_restock?/1 returns false when above threshold" do
      item = %Item{
        always_in_stock: true,
        quantity: Decimal.new("10"),
        restock_threshold: Decimal.new("5")
      }

      refute Item.needs_restock?(item)
    end

    test "needs_restock?/1 returns false when not always_in_stock" do
      item = %Item{
        always_in_stock: false,
        quantity: Decimal.new("0"),
        restock_threshold: Decimal.new("5")
      }

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
