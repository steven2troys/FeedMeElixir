defmodule FeedMe.Pantry.SyncTest do
  use FeedMe.DataCase

  alias FeedMe.Pantry.Sync
  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures
  alias FeedMe.PantryFixtures

  setup do
    # The Sync GenServer and SyncTaskSupervisor are already started by application.ex.
    # We just need to ensure a clean state and set enabled: true for queue tests.
    user = AccountsFixtures.user_fixture()
    household = HouseholdsFixtures.household_fixture(%{}, user)
    %{user: user, household: household}
  end

  describe "queue_item/2 and pending_count/1" do
    test "adds items to the queue", %{household: household} do
      # Override enabled to true for this test
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      assert Sync.pending_count(household.id) == 0

      Sync.queue_item(household.id, %{
        shopping_item_id: Ecto.UUID.generate(),
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: "gallon",
        pantry_item_id: nil
      })

      # Give cast time to process
      Process.sleep(10)
      assert Sync.pending_count(household.id) == 1
    end

    test "deduplicates by shopping_item_id", %{household: household} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      item_id = Ecto.UUID.generate()

      Sync.queue_item(household.id, %{
        shopping_item_id: item_id,
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: "gallon",
        pantry_item_id: nil
      })

      Sync.queue_item(household.id, %{
        shopping_item_id: item_id,
        name: "Milk",
        quantity: Decimal.new("2"),
        unit: "gallon",
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id) == 1
    end

    test "tracks multiple items", %{household: household} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      Sync.queue_item(household.id, %{
        shopping_item_id: Ecto.UUID.generate(),
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: nil,
        pantry_item_id: nil
      })

      Sync.queue_item(household.id, %{
        shopping_item_id: Ecto.UUID.generate(),
        name: "Eggs",
        quantity: Decimal.new("12"),
        unit: nil,
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id) == 2
    end

    test "does nothing when disabled", %{household: household} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: false)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      Sync.queue_item(household.id, %{
        shopping_item_id: Ecto.UUID.generate(),
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: nil,
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id) == 0
    end
  end

  describe "dequeue_item/2" do
    test "removes item from queue", %{household: household} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      item_id = Ecto.UUID.generate()

      Sync.queue_item(household.id, %{
        shopping_item_id: item_id,
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: nil,
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id) == 1

      Sync.dequeue_item(household.id, item_id)
      Process.sleep(10)
      assert Sync.pending_count(household.id) == 0
    end

    test "does not affect other items", %{household: household} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      item_id_1 = Ecto.UUID.generate()
      item_id_2 = Ecto.UUID.generate()

      Sync.queue_item(household.id, %{
        shopping_item_id: item_id_1,
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: nil,
        pantry_item_id: nil
      })

      Sync.queue_item(household.id, %{
        shopping_item_id: item_id_2,
        name: "Eggs",
        quantity: Decimal.new("12"),
        unit: nil,
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id) == 2

      Sync.dequeue_item(household.id, item_id_1)
      Process.sleep(10)
      assert Sync.pending_count(household.id) == 1
    end
  end

  describe "flush/1" do
    test "clears pending items", %{household: household} do
      Application.put_env(:feed_me, Sync, debounce_ms: 60_000, enabled: true)
      on_exit(fn -> Application.put_env(:feed_me, Sync, debounce_ms: 0, enabled: false) end)

      Sync.queue_item(household.id, %{
        shopping_item_id: Ecto.UUID.generate(),
        name: "Milk",
        quantity: Decimal.new("1"),
        unit: nil,
        pantry_item_id: nil
      })

      Process.sleep(10)
      assert Sync.pending_count(household.id) == 1

      # Flush will run do_sync synchronously — it will fail because no API key,
      # but it should still clear the queue
      Sync.flush(household.id)
      assert Sync.pending_count(household.id) == 0
    end

    test "is a no-op for empty queue", %{household: household} do
      assert Sync.flush(household.id) == :ok
    end
  end

  describe "do_sync/2" do
    test "logs warning when no API key is configured", %{household: household} do
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
          Sync.do_sync(household.id, items)
        end)

      assert log =~ "No API key"
    end
  end

  describe "tool execution" do
    test "update_pantry_item updates quantity", %{household: household} do
      pantry_item =
        PantryFixtures.item_fixture(household, %{name: "Milk", quantity: Decimal.new("2")})

      # Call the tool executor directly via do_sync internals
      # We test the tool execution function by simulating what the AI would call
      result =
        Sync.execute_tool(
          "update_pantry_item",
          %{"pantry_item_id" => pantry_item.id, "quantity_to_add" => 3},
          household.id
        )

      assert result =~ "Updated Milk"
      assert result =~ "added 3"

      updated = FeedMe.Pantry.get_item(pantry_item.id)
      assert Decimal.equal?(updated.quantity, Decimal.new("5"))
    end

    test "create_pantry_item creates a new item", %{household: household} do
      result =
        Sync.execute_tool(
          "create_pantry_item",
          %{
            "name" => "Fresh Tagliatelle",
            "quantity" => 400,
            "unit" => "g",
            "category" => "Pasta"
          },
          household.id
        )

      assert result =~ "Created pantry item: Fresh Tagliatelle"

      items = FeedMe.Pantry.list_items(household.id)
      assert Enum.any?(items, &(&1.name == "Fresh Tagliatelle"))
    end

    test "update_pantry_item returns error for nonexistent item", %{household: household} do
      result =
        Sync.execute_tool(
          "update_pantry_item",
          %{"pantry_item_id" => Ecto.UUID.generate(), "quantity_to_add" => 1},
          household.id
        )

      assert result =~ "Error: Pantry item"
      assert result =~ "not found"
    end
  end
end
