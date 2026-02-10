defmodule FeedMe.MealPlanning.MealPlan do
  @moduledoc """
  Schema for meal plans.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meal_plans" do
    field :name, :string
    field :start_date, :date
    field :end_date, :date
    field :status, Ecto.Enum, values: [:draft, :active, :completed, :archived], default: :draft
    field :notes, :string
    field :ai_generated, :boolean, default: false

    belongs_to :household, FeedMe.Households.Household
    belongs_to :created_by, FeedMe.Accounts.User
    belongs_to :approved_by, FeedMe.Accounts.User

    has_many :items, FeedMe.MealPlanning.MealPlanItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(meal_plan, attrs) do
    meal_plan
    |> cast(attrs, [
      :name,
      :start_date,
      :end_date,
      :status,
      :notes,
      :ai_generated,
      :household_id,
      :created_by_id,
      :approved_by_id
    ])
    |> validate_required([:name, :start_date, :end_date, :household_id])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_date_range()
    |> foreign_key_constraint(:household_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:approved_by_id)
  end

  defp validate_date_range(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && Date.compare(end_date, start_date) == :lt do
      add_error(changeset, :end_date, "must be on or after start date")
    else
      changeset
    end
  end
end
