defmodule FeedMe.Budgets.Transaction do
  @moduledoc """
  Schema for budget transactions (purchases).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "budget_transactions" do
    field :amount, :decimal
    field :description, :string
    field :category, :string
    field :merchant, :string
    field :receipt_url, :string
    field :transaction_date, :date
    field :ai_initiated, :boolean, default: false

    belongs_to :budget, FeedMe.Budgets.Budget
    belongs_to :shopping_list, FeedMe.Shopping.List
    belongs_to :recorded_by, FeedMe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :amount,
      :description,
      :category,
      :merchant,
      :receipt_url,
      :transaction_date,
      :ai_initiated,
      :budget_id,
      :shopping_list_id,
      :recorded_by_id
    ])
    |> validate_required([:amount, :transaction_date, :budget_id])
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:budget_id)
    |> foreign_key_constraint(:shopping_list_id)
  end
end
