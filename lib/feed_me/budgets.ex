defmodule FeedMe.Budgets do
  @moduledoc """
  The Budgets context manages household budgets and spending tracking.
  """

  import Ecto.Query, warn: false
  alias FeedMe.Budgets.{Budget, Transaction}
  alias FeedMe.Repo

  # =============================================================================
  # Budgets
  # =============================================================================

  @doc """
  Gets the active budget for a household.
  """
  def get_active_budget(household_id) do
    Budget
    |> where([b], b.household_id == ^household_id)
    |> where([b], is_nil(b.end_date) or b.end_date >= ^Date.utc_today())
    |> order_by([b], desc: b.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets a budget by ID.
  """
  def get_budget(id), do: Repo.get(Budget, id)

  @doc """
  Gets a budget ensuring it belongs to the household.
  """
  def get_budget(id, household_id) do
    Budget
    |> where([b], b.id == ^id and b.household_id == ^household_id)
    |> Repo.one()
  end

  @doc """
  Lists all budgets for a household.
  """
  def list_budgets(household_id) do
    Budget
    |> where([b], b.household_id == ^household_id)
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a budget.
  """
  def create_budget(attrs) do
    %Budget{}
    |> Budget.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a budget.
  """
  def update_budget(%Budget{} = budget, attrs) do
    budget
    |> Budget.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a budget.
  """
  def delete_budget(%Budget{} = budget) do
    Repo.delete(budget)
  end

  @doc """
  Returns a changeset for tracking budget changes.
  """
  def change_budget(%Budget{} = budget, attrs \\ %{}) do
    Budget.changeset(budget, attrs)
  end

  # =============================================================================
  # Transactions
  # =============================================================================

  @doc """
  Records a transaction against a budget.
  """
  def record_transaction(attrs) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists transactions for a budget.
  """
  def list_transactions(budget_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)

    query =
      Transaction
      |> where([t], t.budget_id == ^budget_id)
      |> order_by([t], desc: t.transaction_date)

    query =
      if start_date do
        where(query, [t], t.transaction_date >= ^start_date)
      else
        query
      end

    query =
      if end_date do
        where(query, [t], t.transaction_date <= ^end_date)
      else
        query
      end

    query
    |> limit(^limit)
    |> preload(:recorded_by)
    |> Repo.all()
  end

  @doc """
  Gets the total spent for a budget in the current period.
  """
  def get_period_spending(%Budget{} = budget) do
    start_date = Budget.current_period_start(budget)
    end_date = Budget.current_period_end(budget)

    query =
      Transaction
      |> where([t], t.budget_id == ^budget.id)
      |> where([t], t.transaction_date >= ^start_date)

    query =
      if end_date do
        where(query, [t], t.transaction_date <= ^end_date)
      else
        query
      end

    query
    |> select([t], sum(t.amount))
    |> Repo.one()
    |> case do
      nil -> Decimal.new(0)
      amount -> amount
    end
  end

  @doc """
  Gets the remaining budget for the current period.
  """
  def get_remaining(%Budget{} = budget) do
    spent = get_period_spending(budget)
    Decimal.sub(budget.amount, spent)
  end

  @doc """
  Checks if spending has exceeded the alert threshold.
  """
  def alert_threshold_exceeded?(%Budget{alert_threshold: nil}), do: false

  def alert_threshold_exceeded?(%Budget{} = budget) do
    spent = get_period_spending(budget)
    threshold_amount = Decimal.mult(budget.amount, Decimal.div(budget.alert_threshold, 100))
    Decimal.compare(spent, threshold_amount) != :lt
  end

  @doc """
  Gets budget summary including spending stats.
  """
  def get_budget_summary(%Budget{} = budget) do
    spent = get_period_spending(budget)
    remaining = Decimal.sub(budget.amount, spent)

    percentage_used =
      if Decimal.compare(budget.amount, Decimal.new(0)) == :gt do
        Decimal.mult(Decimal.div(spent, budget.amount), 100)
        |> Decimal.round(1)
      else
        Decimal.new(0)
      end

    %{
      budget: budget,
      spent: spent,
      remaining: remaining,
      percentage_used: percentage_used,
      period_start: Budget.current_period_start(budget),
      period_end: Budget.current_period_end(budget),
      alert_triggered: alert_threshold_exceeded?(budget)
    }
  end

  # =============================================================================
  # AI Authority
  # =============================================================================

  @doc """
  Checks if the AI can automatically add items to shopping list.
  """
  def ai_can_auto_add?(%Budget{ai_authority: authority}) do
    authority in [:auto_add, :auto_purchase]
  end

  @doc """
  Checks if the AI can automatically make purchases.
  """
  def ai_can_auto_purchase?(%Budget{ai_authority: :auto_purchase}), do: true
  def ai_can_auto_purchase?(_), do: false

  @doc """
  Checks if a proposed purchase is within budget.
  """
  def within_budget?(%Budget{} = budget, amount) do
    remaining = get_remaining(budget)
    Decimal.compare(remaining, Decimal.new(amount)) != :lt
  end
end
