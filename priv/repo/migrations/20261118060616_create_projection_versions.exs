defmodule EmberLine.Repo.Migrations.CreateProjectionVersions do
  @moduledoc """
  Bookkeeping table for Commanded.Projections.Ecto: the last event each
  projection has handled. Same shape as the library's own migration.
  """
  use Ecto.Migration

  def change do
    create table(:projection_versions, primary_key: false) do
      add :projection_name, :text, primary_key: true
      add :last_seen_event_number, :bigint

      timestamps(type: :naive_datetime_usec)
    end
  end
end
