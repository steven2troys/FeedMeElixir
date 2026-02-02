defmodule FeedMe.BudgetsTest do
  use FeedMe.DataCase

  alias FeedMe.Budgets
  alias FeedMe.Budgets.{Budget, Transaction}
  alias FeedMe.AccountsFixtures
  alias FeedMe.HouseholdsFixtures

  describe "budgets" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "create_budget/1 creates a budget", %{household: household, user: user} do
      attrs = %{
        period_type: :monthly,
        amount: Decimal.new("500"),
        household_id: household.id,
        created_by_id: user.id
      }

      assert {:ok, %Budget{} = budget} = Budgets.create_budget(attrs)
      assert budget.period_type == :monthly
      assert Decimal.equal?(budget.amount, Decimal.new("500"))
    end

    test "get_active_budget/1 returns the active budget", %{household: household} do
      {:ok, budget} =
        Budgets.create_budget(%{
          period_type: :weekly,
          amount: Decimal.new("200"),
          household_id: household.id
        })

      active = Budgets.get_active_budget(household.id)
      assert active.id == budget.id
    end

    test "get_active_budget/1 excludes expired budgets", %{household: household} do
      # Create expired budget
      {:ok, _expired} =
        Budgets.create_budget(%{
          period_type: :custom,
          amount: Decimal.new("100"),
          household_id: household.id,
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-01-31]
        })

      # Should return nil since budget is expired
      assert Budgets.get_active_budget(household.id) == nil
    end

    test "update_budget/2 updates a budget", %{household: household} do
      {:ok, budget} =
        Budgets.create_budget(%{
          period_type: :weekly,
          amount: Decimal.new("200"),
          household_id: household.id
        })

      {:ok, updated} = Budgets.update_budget(budget, %{amount: Decimal.new("300")})
      assert Decimal.equal?(updated.amount, Decimal.new("300"))
    end

    test "delete_budget/1 deletes a budget", %{household: household} do
      {:ok, budget} =
        Budgets.create_budget(%{
          period_type: :weekly,
          amount: Decimal.new("200"),
          household_id: household.id
        })

      {:ok, _} = Budgets.delete_budget(budget)
      assert Budgets.get_budget(budget.id) == nil
    end
  end

  describe "transactions" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      {:ok, budget} =
        Budgets.create_budget(%{
          period_type: :weekly,
          amount: Decimal.new("200"),
          household_id: household.id
        })

      %{user: user, household: household, budget: budget}
    end

    test "record_transaction/1 creates a transaction", %{budget: budget, user: user} do
      attrs = %{
        amount: Decimal.new("25.50"),
        description: "Groceries",
        merchant: "Safeway",
        transaction_date: Date.utc_today(),
        budget_id: budget.id,
        recorded_by_id: user.id
      }

      assert {:ok, %Transaction{} = transaction} = Budgets.record_transaction(attrs)
      assert Decimal.equal?(transaction.amount, Decimal.new("25.50"))
    end

    test "list_transactions/1 returns transactions for a budget", %{budget: budget} do
      {:ok, _tx1} =
        Budgets.record_transaction(%{
          amount: Decimal.new("10"),
          transaction_date: Date.utc_today(),
          budget_id: budget.id
        })

      {:ok, _tx2} =
        Budgets.record_transaction(%{
          amount: Decimal.new("20"),
          transaction_date: Date.utc_today(),
          budget_id: budget.id
        })

      transactions = Budgets.list_transactions(budget.id)
      assert length(transactions) == 2
    end

    test "get_period_spending/1 calculates total spent", %{budget: budget} do
      {:ok, _} =
        Budgets.record_transaction(%{
          amount: Decimal.new("25"),
          transaction_date: Date.utc_today(),
          budget_id: budget.id
        })

      {:ok, _} =
        Budgets.record_transaction(%{
          amount: Decimal.new("15"),
          transaction_date: Date.utc_today(),
          budget_id: budget.id
        })

      spent = Budgets.get_period_spending(budget)
      assert Decimal.equal?(spent, Decimal.new("40"))
    end

    test "get_remaining/1 calculates remaining budget", %{budget: budget} do
      {:ok, _} =
        Budgets.record_transaction(%{
          amount: Decimal.new("50"),
          transaction_date: Date.utc_today(),
          budget_id: budget.id
        })

      remaining = Budgets.get_remaining(budget)
      # 200 - 50 = 150
      assert Decimal.equal?(remaining, Decimal.new("150"))
    end
  end

  describe "ai_authority" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)
      %{user: user, household: household}
    end

    test "ai_can_auto_add?/1 returns true for auto_add", %{household: household} do
      {:ok, budget} =
        Budgets.create_budget(%{
          period_type: :weekly,
          amount: Decimal.new("200"),
          ai_authority: :auto_add,
          household_id: household.id
        })

      assert Budgets.ai_can_auto_add?(budget) == true
    end

    test "ai_can_auto_add?/1 returns false for recommend", %{household: household} do
      {:ok, budget} =
        Budgets.create_budget(%{
          period_type: :weekly,
          amount: Decimal.new("200"),
          ai_authority: :recommend,
          household_id: household.id
        })

      assert Budgets.ai_can_auto_add?(budget) == false
    end

    test "ai_can_auto_purchase?/1 returns true only for auto_purchase", %{household: household} do
      {:ok, budget} =
        Budgets.create_budget(%{
          period_type: :weekly,
          amount: Decimal.new("200"),
          ai_authority: :auto_purchase,
          household_id: household.id
        })

      assert Budgets.ai_can_auto_purchase?(budget) == true
    end

    test "within_budget?/2 checks if amount is within budget", %{household: household} do
      {:ok, budget} =
        Budgets.create_budget(%{
          period_type: :weekly,
          amount: Decimal.new("100"),
          household_id: household.id
        })

      assert Budgets.within_budget?(budget, 50) == true
      assert Budgets.within_budget?(budget, 150) == false
    end
  end

  describe "alert_threshold" do
    setup do
      user = AccountsFixtures.user_fixture()
      household = HouseholdsFixtures.household_fixture(%{}, user)

      {:ok, budget} =
        Budgets.create_budget(%{
          period_type: :weekly,
          amount: Decimal.new("100"),
          alert_threshold: Decimal.new("80"),
          household_id: household.id
        })

      %{budget: budget}
    end

    test "alert_threshold_exceeded?/1 returns false when under threshold", %{budget: budget} do
      {:ok, _} =
        Budgets.record_transaction(%{
          amount: Decimal.new("50"),
          transaction_date: Date.utc_today(),
          budget_id: budget.id
        })

      assert Budgets.alert_threshold_exceeded?(budget) == false
    end

    test "alert_threshold_exceeded?/1 returns true when over threshold", %{budget: budget} do
      {:ok, _} =
        Budgets.record_transaction(%{
          amount: Decimal.new("85"),
          transaction_date: Date.utc_today(),
          budget_id: budget.id
        })

      assert Budgets.alert_threshold_exceeded?(budget) == true
    end
  end
end
