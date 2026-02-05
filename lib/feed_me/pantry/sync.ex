defmodule FeedMe.Pantry.Sync do
  @moduledoc """
  GenServer that accumulates checked shopping list items per household,
  waits for a debounce period, then fires one AI call to intelligently
  sync them into the pantry (fuzzy matching, unit conversion, etc.).
  """

  use GenServer
  require Logger

  alias FeedMe.AI.{ApiKey, OpenRouter}
  alias FeedMe.{Households, Pantry}

  @default_debounce_ms :timer.minutes(10)

  # =============================================================================
  # Public API
  # =============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Queue a checked shopping item for pantry sync.
  """
  def queue_item(household_id, item_attrs) do
    if enabled?() do
      GenServer.cast(__MODULE__, {:queue_item, household_id, item_attrs})
    end
  end

  @doc """
  Remove an item from the queue (e.g., when unchecked before flush).
  """
  def dequeue_item(household_id, shopping_item_id) do
    if enabled?() do
      GenServer.cast(__MODULE__, {:dequeue_item, household_id, shopping_item_id})
    end
  end

  @doc """
  Immediately process pending items for a household. Useful for testing.
  """
  def flush(household_id) do
    GenServer.call(__MODULE__, {:flush, household_id})
  end

  @doc """
  Returns the number of pending items for a household.
  """
  def pending_count(household_id) do
    GenServer.call(__MODULE__, {:pending_count, household_id})
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:queue_item, household_id, item_attrs}, state) do
    Logger.info("Pantry.Sync: Queued item '#{item_attrs.name}' for household #{household_id}")
    entry = Map.get(state, household_id, %{items: [], timer_ref: nil})

    # Cancel existing timer
    if entry.timer_ref, do: Process.cancel_timer(entry.timer_ref)

    # Deduplicate by shopping_item_id (latest wins)
    items =
      entry.items
      |> Enum.reject(&(&1.shopping_item_id == item_attrs.shopping_item_id))
      |> List.insert_at(-1, item_attrs)

    # Start new debounce timer
    timer_ref = Process.send_after(self(), {:flush, household_id}, debounce_ms())

    {:noreply, Map.put(state, household_id, %{items: items, timer_ref: timer_ref})}
  end

  @impl true
  def handle_cast({:dequeue_item, household_id, shopping_item_id}, state) do
    case Map.get(state, household_id) do
      nil ->
        {:noreply, state}

      entry ->
        items = Enum.reject(entry.items, &(&1.shopping_item_id == shopping_item_id))

        if items == [] do
          # No more items — cancel timer, remove household entry
          if entry.timer_ref, do: Process.cancel_timer(entry.timer_ref)
          {:noreply, Map.delete(state, household_id)}
        else
          {:noreply, Map.put(state, household_id, %{entry | items: items})}
        end
    end
  end

  @impl true
  def handle_call({:flush, household_id}, _from, state) do
    case Map.pop(state, household_id) do
      {nil, state} ->
        {:reply, :ok, state}

      {entry, state} ->
        if entry.timer_ref, do: Process.cancel_timer(entry.timer_ref)

        if entry.items != [] do
          do_sync(household_id, entry.items)
        end

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:pending_count, household_id}, _from, state) do
    count =
      case Map.get(state, household_id) do
        nil -> 0
        entry -> length(entry.items)
      end

    {:reply, count, state}
  end

  @impl true
  def handle_info({:flush, household_id}, state) do
    case Map.pop(state, household_id) do
      {nil, state} ->
        {:noreply, state}

      {entry, state} ->
        if entry.items != [] do
          Logger.info("Pantry.Sync: Flushing #{length(entry.items)} items for household #{household_id}")
          Task.Supervisor.start_child(FeedMe.Pantry.SyncTaskSupervisor, fn ->
            do_sync(household_id, entry.items)
          end)
        end

        {:noreply, state}
    end
  end

  # =============================================================================
  # Sync Logic (runs in spawned Task)
  # =============================================================================

  @doc false
  def do_sync(household_id, items) do
    Logger.info("Pantry.Sync: Starting sync for #{length(items)} items")

    with api_key_record when not is_nil(api_key_record) <-
           FeedMe.AI.get_api_key(household_id, "openrouter"),
         decrypted_key when is_binary(decrypted_key) <- ApiKey.decrypt_key(api_key_record) do
      household = Households.get_household(household_id)
      model = (household && household.selected_model) || "anthropic/claude-3.5-sonnet"

      pantry_items = Pantry.list_items(household_id)
      categories = Pantry.list_categories(household_id)

      messages = build_messages(pantry_items, categories, items)
      tools = tool_definitions()

      run_ai_loop(decrypted_key, messages, tools, model, household_id, 0)
    else
      nil ->
        Logger.warning("Pantry.Sync: No API key for household #{household_id}, dropping #{length(items)} items")
        :ok
    end
  end

  defp run_ai_loop(_api_key, _messages, _tools, _model, _household_id, round) when round >= 3 do
    Logger.warning("Pantry.Sync: Reached max rounds (3), stopping")
    :ok
  end

  defp run_ai_loop(api_key, messages, tools, model, household_id, round) do
    case OpenRouter.chat(api_key, messages, model: model, tools: tools) do
      {:ok, response} ->
        if response.tool_calls && response.tool_calls != [] do
          tool_results = execute_tool_calls(response.tool_calls, household_id)

          updated_messages =
            messages ++
              [
                %{role: :assistant, content: response.content, tool_calls: response.tool_calls}
                | Enum.map(tool_results, fn result ->
                    %{role: :tool, content: result.content, tool_call_id: result.tool_call_id}
                  end)
              ]

          run_ai_loop(api_key, updated_messages, tools, model, household_id, round + 1)
        else
          Logger.info("Pantry.Sync: Completed for household #{household_id}")
          :ok
        end

      {:error, reason} ->
        Logger.warning("Pantry.Sync: AI call failed for household #{household_id}: #{inspect(reason)}")
        :ok
    end
  end

  defp execute_tool_calls(tool_calls, household_id) do
    Enum.map(tool_calls, fn tool_call ->
      function = tool_call["function"]
      tool_name = function["name"]
      args = Jason.decode!(function["arguments"])

      result = execute_tool(tool_name, args, household_id)
      Logger.info("Pantry.Sync: #{tool_name} -> #{result}")

      %{tool_call_id: tool_call["id"], content: result}
    end)
  end

  @doc false
  def execute_tool("update_pantry_item", args, household_id) do
    pantry_item_id = args["pantry_item_id"]
    quantity_to_add = args["quantity_to_add"]

    case Pantry.get_item(pantry_item_id, household_id) do
      nil ->
        "Error: Pantry item #{pantry_item_id} not found"

      item ->
        case Pantry.add_to_item(item, quantity_to_add, nil, reason: "Auto-added from shopping list") do
          {:ok, updated} ->
            "Updated #{updated.name}: added #{quantity_to_add}, new quantity: #{updated.quantity}"

          {:error, reason} ->
            "Error updating #{item.name}: #{inspect(reason)}"
        end
    end
  end

  @doc false
  def execute_tool("create_pantry_item", args, household_id) do
    category_id =
      case args["category"] do
        nil -> nil
        "" -> nil
        category_name ->
          case Pantry.find_or_create_category(household_id, category_name) do
            {:ok, cat} -> cat.id
            _ -> nil
          end
      end

    attrs = %{
      name: args["name"],
      quantity: Decimal.new("#{args["quantity"] || 1}"),
      unit: args["unit"],
      category_id: category_id,
      household_id: household_id
    }

    case Pantry.create_item(attrs) do
      {:ok, item} ->
        "Created pantry item: #{item.name} (#{item.quantity} #{item.unit || "units"})"

      {:error, changeset} ->
        "Error creating #{args["name"]}: #{inspect(changeset.errors)}"
    end
  end

  @doc false
  def execute_tool(unknown, _args, _household_id) do
    "Error: Unknown tool #{unknown}"
  end

  # =============================================================================
  # AI Messages & Tools
  # =============================================================================

  defp build_messages(pantry_items, _categories, shopping_items) do
    pantry_text =
      if pantry_items == [] do
        "(pantry is empty)"
      else
        pantry_items
        |> Enum.map(fn item ->
          category_name = if item.category, do: item.category.name, else: "Uncategorized"
          "- ID: #{item.id} | \"#{item.name}\" | #{item.quantity} #{item.unit || "units"} | #{category_name}"
        end)
        |> Enum.join("\n")
      end

    shopping_text =
      shopping_items
      |> Enum.with_index(1)
      |> Enum.map(fn {item, idx} ->
        parts = ["\"#{item.name}\""]
        parts = if item.quantity, do: parts ++ ["qty: #{item.quantity}"], else: parts
        parts = if item.unit, do: parts ++ ["unit: #{item.unit}"], else: parts

        parts =
          if item.pantry_item_id,
            do: parts ++ ["pre-linked pantry_item_id: #{item.pantry_item_id}"],
            else: parts

        "#{idx}. #{Enum.join(parts, ", ")}"
      end)
      |> Enum.join("\n")

    [
      %{role: :system, content: system_prompt()},
      %{
        role: :user,
        content: """
        Current pantry:
        #{pantry_text}

        Items checked off shopping list:
        #{shopping_text}
        """
      }
    ]
  end

  defp system_prompt do
    """
    You are a pantry inventory assistant. Items were checked off a shopping list, \
    meaning the user acquired them. Update the pantry accordingly.

    Rules:
    - Match shopping items to existing pantry items by name (fuzzy, case-insensitive). \
    Prefer updating existing items over creating duplicates.
    - Convert units when they differ (e.g., shopping "400g" → pantry tracks in "lbs" → add ~0.88).
    - If no match exists, create a new pantry item.
    - If a shopping item has no unit or quantity, use reasonable defaults (qty: 1).
    - If a shopping item has a pre-linked pantry_item_id, use that item's ID for the update.
    - Process ALL items. Do not skip any.
    """
  end

  defp tool_definitions do
    [
      %{
        type: "function",
        function: %{
          name: "update_pantry_item",
          description:
            "Update quantity of an existing pantry item. Convert units to the pantry item's native unit before adding.",
          parameters: %{
            type: "object",
            properties: %{
              pantry_item_id: %{type: "string", description: "The UUID of the existing pantry item to update"},
              quantity_to_add: %{type: "number", description: "The quantity to add, converted to the pantry item's unit"},
              notes: %{type: "string", description: "Optional notes about the update"}
            },
            required: ["pantry_item_id", "quantity_to_add"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "create_pantry_item",
          description: "Create a new pantry item for something not already in the pantry.",
          parameters: %{
            type: "object",
            properties: %{
              name: %{type: "string", description: "Name of the pantry item"},
              quantity: %{type: "number", description: "Initial quantity"},
              unit: %{type: "string", description: "Unit of measurement (e.g., lbs, kg, gallons, count)"},
              category: %{type: "string", description: "Category name (e.g., Dairy, Produce, Meat & Seafood)"}
            },
            required: ["name", "quantity"]
          }
        }
      }
    ]
  end

  # =============================================================================
  # Config Helpers
  # =============================================================================

  defp debounce_ms do
    Application.get_env(:feed_me, __MODULE__, [])
    |> Keyword.get(:debounce_ms, @default_debounce_ms)
  end

  defp enabled? do
    Application.get_env(:feed_me, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end
end
