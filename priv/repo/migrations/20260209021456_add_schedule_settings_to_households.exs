defmodule FeedMe.Repo.Migrations.AddScheduleSettingsToHouseholds do
  use Ecto.Migration

  def change do
    alter table(:households) do
      add :weekly_suggestion_enabled, :boolean, null: false, default: false
      add :weekly_suggestion_day, :integer, null: false, default: 7
      add :daily_pantry_check_enabled, :boolean, null: false, default: false
    end
  end
end
