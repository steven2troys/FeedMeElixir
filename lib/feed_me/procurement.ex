defmodule FeedMe.Procurement do
  @moduledoc """
  The Procurement context manages procurement plans for purchasing
  groceries and supplies from approved suppliers.
  """

  import Ecto.Query, warn: false
  alias FeedMe.Repo
  alias FeedMe.Procurement.{ProcurementItem, ProcurementPlan}
  alias FeedMe.{MealPlanning, Pantry, Shopping, Suppliers}

  # =============================================================================
  # PubSub
  # =============================================================================

  def subscribe(household_id) do
    Phoenix.PubSub.subscribe(FeedMe.PubSub, topic(household_id))
  end

  defp topic(household_id), do: "procurement:#{household_id}"

  defp broadcast(household_id, event) do
    Phoenix.PubSub.broadcast(FeedMe.PubSub, topic(household_id), event)
  end

  # =============================================================================
  # Procurement Plans
  # =============================================================================

  @doc """
  Lists procurement plans for a household.
  """
  def list_plans(household_id, opts \\ []) do
    query =
      ProcurementPlan
      |> where([p], p.household_id == ^household_id)
      |> order_by([p], desc: p.inserted_at)

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [p], p.status == ^status)
      end

    Repo.all(query)
  end

  @doc """
  Gets a procurement plan by ID, scoped to a household.
  """
  def get_plan(id, household_id) do
    ProcurementPlan
    |> where([p], p.id == ^id and p.household_id == ^household_id)
    |> Repo.one()
  end

  @doc """
  Gets a procurement plan with items preloaded.
  """
  def get_plan_with_items(id, household_id) do
    ProcurementPlan
    |> where([p], p.id == ^id and p.household_id == ^household_id)
    |> preload(items: :supplier)
    |> Repo.one()
  end

  @doc """
  Creates a procurement plan.
  """
  def create_plan(attrs) do
    result =
      %ProcurementPlan{}
      |> ProcurementPlan.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, plan} ->
        broadcast(plan.household_id, {:procurement_plan_created, plan})
        {:ok, plan}

      error ->
        error
    end
  end

  @doc """
  Updates a procurement plan.
  """
  def update_plan(%ProcurementPlan{} = plan, attrs) do
    result =
      plan
      |> ProcurementPlan.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, plan} ->
        broadcast(plan.household_id, {:procurement_plan_updated, plan})
        {:ok, plan}

      error ->
        error
    end
  end

  @doc """
  Deletes a procurement plan.
  """
  def delete_plan(%ProcurementPlan{} = plan) do
    result = Repo.delete(plan)

    case result do
      {:ok, plan} ->
        broadcast(plan.household_id, {:procurement_plan_deleted, plan})
        {:ok, plan}

      error ->
        error
    end
  end

  @doc """
  Returns a changeset for a procurement plan.
  """
  def change_plan(%ProcurementPlan{} = plan, attrs \\ %{}) do
    ProcurementPlan.changeset(plan, attrs)
  end

  # =============================================================================
  # Procurement Items
  # =============================================================================

  @doc """
  Lists items for a procurement plan.
  """
  def list_items(plan_id) do
    ProcurementItem
    |> where([i], i.procurement_plan_id == ^plan_id)
    |> order_by([i], asc: i.category, asc: i.name)
    |> preload(:supplier)
    |> Repo.all()
  end

  @doc """
  Gets a procurement item by ID.
  """
  def get_item(id) do
    ProcurementItem
    |> preload(:supplier)
    |> Repo.get(id)
  end

  @doc """
  Creates a procurement item.
  """
  def create_item(attrs) do
    %ProcurementItem{}
    |> ProcurementItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a procurement item.
  """
  def update_item(%ProcurementItem{} = item, attrs) do
    item
    |> ProcurementItem.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a procurement item.
  """
  def delete_item(%ProcurementItem{} = item) do
    Repo.delete(item)
  end

  # =============================================================================
  # Plan Creation Helpers
  # =============================================================================

  @doc """
  Creates a procurement plan from a meal plan's shopping needs.
  """
  def create_from_meal_plan(meal_plan, user) do
    needs = MealPlanning.calculate_shopping_needs(meal_plan)

    if needs == [] do
      {:ok, :no_needs}
    else
      # Get default supplier
      default_hs = Suppliers.get_default_supplier(meal_plan.household_id)
      default_supplier = default_hs && Repo.preload(default_hs, :supplier).supplier

      plan_attrs = %{
        name: "Groceries for #{meal_plan.name}",
        household_id: meal_plan.household_id,
        meal_plan_id: meal_plan.id,
        created_by_id: user.id,
        source: :meal_plan,
        ai_generated: false,
        status: :suggested
      }

      case create_plan(plan_attrs) do
        {:ok, plan} ->
          items =
            Enum.map(needs, fn need ->
              deep_link =
                if default_supplier do
                  Suppliers.generate_deep_link(default_supplier, need.name)
                end

              %{
                name: need.name,
                quantity: need.need,
                unit: need.unit,
                procurement_plan_id: plan.id,
                pantry_item_id: need.pantry_item_id,
                supplier_id: default_supplier && default_supplier.id,
                deep_link_url: deep_link
              }
            end)

          Enum.each(items, &create_item/1)

          # Calculate estimated total
          plan = get_plan_with_items(plan.id, plan.household_id)
          {:ok, plan}

        error ->
          error
      end
    end
  end

  @doc """
  Creates a procurement plan from items needing restock.
  """
  def create_from_restock(household_id, user) do
    items = Pantry.items_needing_restock(household_id)

    if items == [] do
      {:ok, :no_needs}
    else
      default_hs = Suppliers.get_default_supplier(household_id)
      default_supplier = default_hs && Repo.preload(default_hs, :supplier).supplier

      plan_attrs = %{
        name: "Restock - #{Calendar.strftime(Date.utc_today(), "%b %d")}",
        household_id: household_id,
        created_by_id: user.id,
        source: :restock,
        status: :suggested
      }

      case create_plan(plan_attrs) do
        {:ok, plan} ->
          Enum.each(items, fn item ->
            deep_link =
              if default_supplier do
                Suppliers.generate_deep_link(default_supplier, item.name)
              end

            create_item(%{
              name: item.name,
              quantity: item.restock_threshold || Decimal.new(1),
              unit: item.unit,
              procurement_plan_id: plan.id,
              pantry_item_id: item.id,
              supplier_id: default_supplier && default_supplier.id,
              deep_link_url: deep_link,
              category: item.category && item.category.name
            })
          end)

          plan = get_plan_with_items(plan.id, plan.household_id)
          {:ok, plan}

        error ->
          error
      end
    end
  end

  @doc """
  Creates a procurement plan from expiring items.
  """
  def create_from_expiring(household_id, user, days \\ 7) do
    items = Pantry.items_expiring_soon(household_id, days)

    if items == [] do
      {:ok, :no_needs}
    else
      default_hs = Suppliers.get_default_supplier(household_id)
      default_supplier = default_hs && Repo.preload(default_hs, :supplier).supplier

      plan_attrs = %{
        name: "Replace Expiring Items - #{Calendar.strftime(Date.utc_today(), "%b %d")}",
        household_id: household_id,
        created_by_id: user.id,
        source: :expiring,
        status: :suggested
      }

      case create_plan(plan_attrs) do
        {:ok, plan} ->
          Enum.each(items, fn item ->
            deep_link =
              if default_supplier do
                Suppliers.generate_deep_link(default_supplier, item.name)
              end

            create_item(%{
              name: item.name,
              quantity: item.quantity || Decimal.new(1),
              unit: item.unit,
              procurement_plan_id: plan.id,
              pantry_item_id: item.id,
              supplier_id: default_supplier && default_supplier.id,
              deep_link_url: deep_link,
              category: item.category && item.category.name,
              notes: "Expires #{item.expiration_date}"
            })
          end)

          plan = get_plan_with_items(plan.id, plan.household_id)
          {:ok, plan}

        error ->
          error
      end
    end
  end

  # =============================================================================
  # Status Transitions
  # =============================================================================

  @doc """
  Approves a procurement plan.
  """
  def approve_plan(%ProcurementPlan{} = plan, user) do
    update_plan(plan, %{status: :approved, approved_by_id: user.id})
  end

  @doc """
  Marks a procurement plan as currently being shopped.
  """
  def mark_shopping(%ProcurementPlan{} = plan) do
    update_plan(plan, %{status: :shopping})
  end

  @doc """
  Fulfills a procurement plan and calculates actual total.
  """
  def fulfill_plan(%ProcurementPlan{} = plan) do
    plan = Repo.preload(plan, :items)

    actual_total =
      plan.items
      |> Enum.filter(&(&1.status == :purchased))
      |> Enum.reduce(Decimal.new(0), fn item, total ->
        price = item.actual_price || item.estimated_price || Decimal.new(0)
        Decimal.add(total, price)
      end)

    update_plan(plan, %{status: :fulfilled, actual_total: actual_total})
  end

  @doc """
  Cancels a procurement plan.
  """
  def cancel_plan(%ProcurementPlan{} = plan) do
    update_plan(plan, %{status: :cancelled})
  end

  # =============================================================================
  # Shopping List Sync
  # =============================================================================

  @doc """
  Syncs approved procurement items to the main shopping list.
  """
  def sync_to_shopping_list(%ProcurementPlan{} = plan, user) do
    plan = Repo.preload(plan, :items)
    main_list = Shopping.get_or_create_main_list(plan.household_id)

    added =
      plan.items
      |> Enum.filter(&(&1.status == :needed))
      |> Enum.reduce(0, fn item, count ->
        attrs = %{
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          shopping_list_id: main_list.id,
          pantry_item_id: item.pantry_item_id,
          added_by_id: user.id
        }

        case Shopping.create_item(attrs) do
          {:ok, shopping_item} ->
            update_item(item, %{shopping_item_id: shopping_item.id, status: :in_cart})
            count + 1

          _ ->
            count
        end
      end)

    {:ok, %{added: added}}
  end

  # =============================================================================
  # Budget Check
  # =============================================================================

  @doc """
  Checks procurement plan estimated total against remaining budget.
  """
  def check_budget(%ProcurementPlan{} = plan) do
    plan = Repo.preload(plan, :items)

    estimated =
      plan.items
      |> Enum.filter(&(&1.status != :skipped))
      |> Enum.reduce(Decimal.new(0), fn item, total ->
        price = item.estimated_price || Decimal.new(0)
        Decimal.add(total, price)
      end)

    %{
      estimated_total: estimated,
      item_count: length(plan.items)
    }
  end
end
