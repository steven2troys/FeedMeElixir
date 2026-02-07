defmodule FeedMe.Repo.Migrations.AddShoppingListSharing do
  use Ecto.Migration

  def change do
    alter table(:shopping_lists) do
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create table(:shopping_list_shares, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :shopping_list_id,
          references(:shopping_lists, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shopping_list_shares, [:shopping_list_id, :user_id])
    create index(:shopping_list_shares, [:user_id])
  end
end
