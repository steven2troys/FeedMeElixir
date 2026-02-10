defmodule FeedMe.Procurement.ProcurementPlan do
  @moduledoc """
  Schema for procurement plans.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "procurement_plans" do
    field :name, :string

    field :status, Ecto.Enum,
      values: [:suggested, :approved, :shopping, :fulfilled, :cancelled],
      default: :suggested

    field :estimated_total, :decimal
    field :actual_total, :decimal
    field :notes, :string
    field :ai_generated, :boolean, default: false

    field :source, Ecto.Enum,
      values: [:meal_plan, :restock, :manual, :expiring],
      default: :manual

    belongs_to :household, FeedMe.Households.Household
    belongs_to :meal_plan, FeedMe.MealPlanning.MealPlan
    belongs_to :created_by, FeedMe.Accounts.User
    belongs_to :approved_by, FeedMe.Accounts.User

    has_many :items, FeedMe.Procurement.ProcurementItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :name,
      :status,
      :estimated_total,
      :actual_total,
      :notes,
      :ai_generated,
      :source,
      :household_id,
      :meal_plan_id,
      :created_by_id,
      :approved_by_id
    ])
    |> validate_required([:name, :household_id])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_number(:estimated_total, greater_than_or_equal_to: 0)
    |> validate_number(:actual_total, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:household_id)
    |> foreign_key_constraint(:meal_plan_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:approved_by_id)
  end
end
