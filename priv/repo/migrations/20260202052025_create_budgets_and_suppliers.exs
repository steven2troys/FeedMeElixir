defmodule FeedMe.Repo.Migrations.CreateBudgetsAndSuppliers do
  use Ecto.Migration

  def change do
    # Budgets
    create table(:budgets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # weekly, monthly, custom
      add :period_type, :string, null: false
      add :amount, :decimal, null: false
      add :currency, :string, default: "USD"
      # recommend, auto_add, auto_purchase
      add :ai_authority, :string, default: "recommend"
      # Alert when spending reaches this percentage
      add :alert_threshold, :decimal
      add :rollover_enabled, :boolean, default: false
      add :start_date, :date
      add :end_date, :date

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:budgets, [:household_id])
    create unique_index(:budgets, [:household_id, :period_type], where: "end_date IS NULL")

    # Budget transactions (purchase tracking)
    create table(:budget_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :amount, :decimal, null: false
      add :description, :string
      add :category, :string
      add :merchant, :string
      add :receipt_url, :string
      add :transaction_date, :date, null: false
      add :ai_initiated, :boolean, default: false
      add :budget_id, references(:budgets, type: :binary_id, on_delete: :delete_all), null: false
      add :shopping_list_id, references(:shopping_lists, type: :binary_id, on_delete: :nilify_all)
      add :recorded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:budget_transactions, [:budget_id])
    create index(:budget_transactions, [:budget_id, :transaction_date])

    # Suppliers (external grocery services)
    create table(:suppliers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      # instacart, amazon_fresh, walmart, etc.
      add :code, :string, null: false
      add :api_base_url, :string
      add :logo_url, :string
      add :is_active, :boolean, default: true
      add :supports_aisle_sorting, :boolean, default: false
      add :supports_pricing, :boolean, default: false
      add :supports_delivery, :boolean, default: false
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:suppliers, [:code])

    # Household suppliers (which suppliers a household has enabled)
    create table(:household_suppliers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :is_default, :boolean, default: false
      # Encrypted API credentials
      add :credentials, :binary
      add :settings, :map, default: %{}
      add :last_synced_at, :utc_datetime

      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all),
        null: false

      add :supplier_id, references(:suppliers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :configured_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:household_suppliers, [:household_id])
    create unique_index(:household_suppliers, [:household_id, :supplier_id])
  end
end
