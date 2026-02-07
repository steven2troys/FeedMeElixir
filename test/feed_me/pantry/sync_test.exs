defmodule FeedMe.Pantry.SyncTest do
  use FeedMe.DataCase

  alias FeedMe.Pantry
  alias FeedMe.Pantry.Sync
  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures
  alias FeedMe.PantryFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    household = HouseholdsFixtures.household_fixture(%{}, user)
    location = PantryFixtures.storage_location_fixture(household)
    %{user: user, household: household, location: location}
  end

  describe "queue_item/3 and pending_count/2" do
    test "adds items to the queue", %{household: household, location: location} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      assert Sync.pending_count(household.id, location.id) == 0

      Sync.queue_item(household.id, location.id, %{
        shopping_item_id: Ecto.UUID.generate(),
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: "gallon",
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id, location.id) == 1
    end

    test "deduplicates by shopping_item_id", %{household: household, location: location} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      item_id = Ecto.UUID.generate()

      Sync.queue_item(household.id, location.id, %{
        shopping_item_id: item_id,
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: "gallon",
        pantry_item_id: nil
      })

      Sync.queue_item(household.id, location.id, %{
        shopping_item_id: item_id,
        name: "Milk",
        quantity: Decimal.new("2"),
        unit: "gallon",
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id, location.id) == 1
    end

    test "tracks multiple items", %{household: household, location: location} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      Sync.queue_item(household.id, location.id, %{
        shopping_item_id: Ecto.UUID.generate(),
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: nil,
        pantry_item_id: nil
      })

      Sync.queue_item(household.id, location.id, %{
        shopping_item_id: Ecto.UUID.generate(),
        name: "Eggs",
        quantity: Decimal.new("12"),
        unit: nil,
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id, location.id) == 2
    end

    test "does nothing when disabled", %{household: household, location: location} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: false)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      Sync.queue_item(household.id, location.id, %{
        shopping_item_id: Ecto.UUID.generate(),
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: nil,
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id, location.id) == 0
    end
  end

  describe "dequeue_item/3" do
    test "removes item from queue", %{household: household, location: location} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      item_id = Ecto.UUID.generate()

      Sync.queue_item(household.id, location.id, %{
        shopping_item_id: item_id,
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: nil,
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id, location.id) == 1

      Sync.dequeue_item(household.id, location.id, item_id)
      Process.sleep(10)
      assert Sync.pending_count(household.id, location.id) == 0
    end

    test "does not affect other items", %{household: household, location: location} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      item_id_1 = Ecto.UUID.generate()
      item_id_2 = Ecto.UUID.generate()

      Sync.queue_item(household.id, location.id, %{
        shopping_item_id: item_id_1,
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: nil,
        pantry_item_id: nil
      })

      Sync.queue_item(household.id, location.id, %{
        shopping_item_id: item_id_2,
        name: "Eggs",
        quantity: Decimal.new("12"),
        unit: nil,
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id, location.id) == 2

      Sync.dequeue_item(household.id, location.id, item_id_1)
      Process.sleep(10)
      assert Sync.pending_count(household.id, location.id) == 1
    end
  end

  describe "flush/2" do
    test "clears pending items", %{household: household, location: location} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      Sync.queue_item(household.id, location.id, %{
        shopping_item_id: Ecto.UUID.generate(),
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: nil,
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id, location.id) == 1

      Sync.flush(household.id, location.id)
      assert Sync.pending_count(household.id, location.id) == 0
    end

    test "is a no-op for empty queue", %{household: household, location: location} do
      assert Sync.flush(household.id, location.id) == :ok
    end
  end

  describe "do_sync/3" do
    test "logs warning when no API key is configured", %{
      household: household,
      location: location
    } do
      import ExUnit.CaptureLog

      items = [
        %{
          shopping_item_id: Ecto.UUID.generate(),
          name: "Milk",
          quantity: Decimal.new("1"),
          unit: nil,
          pantry_item_id: nil
        }
      ]

      log =
        capture_log(fn ->
          Sync.do_sync(household.id, location.id, items)
        end)

      assert log =~ "No API key"
    end
  end

  describe "tool execution" do
    test "update_pantry_item updates quantity", %{household: household, location: location} do
      pantry_item =
        PantryFixtures.item_fixture(household, %{name: "Milk", quantity: Decimal.new("2")})

      result =
        Sync.execute_tool(
          "update_pantry_item",
          %{"pantry_item_id" => pantry_item.id, "quantity_to_add" => 3},
          household.id,
          location.id
        )

      assert result =~ "Updated Milk"
      assert result =~ "added 3"

      updated = Pantry.get_item(pantry_item.id)
      assert Decimal.equal?(updated.quantity, Decimal.new("5"))
    end

    test "create_pantry_item creates a new item", %{household: household, location: location} do
      result =
        Sync.execute_tool(
          "create_pantry_item",
          %{
            "name" => "Fresh Tagliatelle",
            "quantity" => 400,
            "unit" => "g",
            "category" => "Pasta"
          },
          household.id,
          location.id
        )

      assert result =~ "Created pantry item: Fresh Tagliatelle"

      items = Pantry.list_items(household.id)
      assert Enum.any?(items, &(&1.name == "Fresh Tagliatelle"))
    end

    test "update_pantry_item returns error for nonexistent item", %{
      household: household,
      location: location
    } do
      result =
        Sync.execute_tool(
          "update_pantry_item",
          %{"pantry_item_id" => Ecto.UUID.generate(), "quantity_to_add" => 1},
          household.id,
          location.id
        )

      assert result =~ "Error: Pantry item"
      assert result =~ "not found"
    end
  end
end
