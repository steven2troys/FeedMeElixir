defmodule FeedMe.Shopping.ListShare do
  @moduledoc """
  Schema for sharing shopping lists with household members.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "shopping_list_shares" do
    belongs_to :shopping_list, FeedMe.Shopping.List
    belongs_to :user, FeedMe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(share, attrs) do
    share
    |> cast(attrs, [:shopping_list_id, :user_id])
    |> validate_required([:shopping_list_id, :user_id])
    |> foreign_key_constraint(:shopping_list_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:shopping_list_id, :user_id])
  end
end
