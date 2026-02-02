defmodule FeedMe.Repo.Migrations.CreateHouseholds do
  use Ecto.Migration

  def change do
    create table(:households, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false, default: "member"
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:memberships, [:user_id])
    create index(:memberships, [:household_id])
    create unique_index(:memberships, [:user_id, :household_id])

    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :token, :string, null: false
      add :role, :string, null: false, default: "member"
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :household_id, references(:households, type: :binary_id, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:invitations, [:household_id])
    create index(:invitations, [:email])
    create unique_index(:invitations, [:token])
  end
end
