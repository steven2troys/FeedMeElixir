defmodule FeedMe.Shopping.List do
  @moduledoc """
  Schema for shopping lists.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "shopping_lists" do
    field :name, :string
    field :is_main, :boolean, default: false
    field :add_to_pantry, :boolean, default: false
    field :status, Ecto.Enum, values: [:active, :completed, :archived], default: :active

    belongs_to :household, FeedMe.Households.Household
    has_many :items, FeedMe.Shopping.Item, foreign_key: :shopping_list_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(list, attrs) do
    list
    |> cast(attrs, [:name, :is_main, :add_to_pantry, :status, :household_id])
    |> validate_required([:name, :household_id])
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:household_id)
    |> enforce_main_list_pantry()
  end

  defp enforce_main_list_pantry(changeset) do
    is_main = get_field(changeset, :is_main)

    if is_main do
      put_change(changeset, :add_to_pantry, true)
    else
      changeset
    end
  end
end
