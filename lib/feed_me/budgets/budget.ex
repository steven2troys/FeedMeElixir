defmodule FeedMe.Budgets.Budget do
  @moduledoc """
  Schema for household budgets.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "budgets" do
    field :period_type, Ecto.Enum, values: [:weekly, :monthly, :custom]
    field :amount, :decimal
    field :currency, :string, default: "USD"
    field :ai_authority, Ecto.Enum, values: [:recommend, :auto_add, :auto_purchase], default: :recommend
    field :alert_threshold, :decimal
    field :rollover_enabled, :boolean, default: false
    field :start_date, :date
    field :end_date, :date

    belongs_to :household, FeedMe.Households.Household
    belongs_to :created_by, FeedMe.Accounts.User
    has_many :transactions, FeedMe.Budgets.Transaction

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(budget, attrs) do
    budget
    |> cast(attrs, [
      :period_type,
      :amount,
      :currency,
      :ai_authority,
      :alert_threshold,
      :rollover_enabled,
      :start_date,
      :end_date,
      :household_id,
      :created_by_id
    ])
    |> validate_required([:period_type, :amount, :household_id])
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:alert_threshold, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_dates()
    |> foreign_key_constraint(:household_id)
  end

  defp validate_dates(changeset) do
    case {get_field(changeset, :start_date), get_field(changeset, :end_date)} do
      {start, end_date} when not is_nil(start) and not is_nil(end_date) ->
        if Date.compare(start, end_date) == :gt do
          add_error(changeset, :end_date, "must be after start date")
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  @doc """
  Checks if a budget is currently active.
  """
  def active?(%__MODULE__{end_date: nil}), do: true

  def active?(%__MODULE__{end_date: end_date}) do
    Date.compare(Date.utc_today(), end_date) != :gt
  end

  @doc """
  Returns the current period start date based on period type.
  """
  def current_period_start(%__MODULE__{period_type: :weekly}) do
    today = Date.utc_today()
    # Get the start of the current week (assuming week starts on Monday)
    day_of_week = Date.day_of_week(today)
    Date.add(today, -(day_of_week - 1))
  end

  def current_period_start(%__MODULE__{period_type: :monthly}) do
    today = Date.utc_today()
    Date.beginning_of_month(today)
  end

  def current_period_start(%__MODULE__{period_type: :custom, start_date: start_date}) do
    start_date || Date.utc_today()
  end

  @doc """
  Returns the current period end date based on period type.
  """
  def current_period_end(%__MODULE__{period_type: :weekly} = budget) do
    start = current_period_start(budget)
    Date.add(start, 6)
  end

  def current_period_end(%__MODULE__{period_type: :monthly}) do
    today = Date.utc_today()
    Date.end_of_month(today)
  end

  def current_period_end(%__MODULE__{period_type: :custom, end_date: end_date}) do
    end_date
  end
end
