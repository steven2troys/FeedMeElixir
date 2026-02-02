defmodule FeedMe.Repo.Migrations.AddSelectedModelToHouseholds do
  use Ecto.Migration

  def change do
    alter table(:households) do
      add :selected_model, :string, default: "anthropic/claude-3.5-sonnet"
    end
  end
end
