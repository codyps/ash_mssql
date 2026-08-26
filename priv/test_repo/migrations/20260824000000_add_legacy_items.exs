defmodule AshMssql.TestRepo.Migrations.AddLegacyItems do
  @moduledoc """
  Hand-written migration for AshMssql.Test.LegacyItem.

  Uniqueness is enforced with table-level UNIQUE KEY constraints (as a DBA
  might create outside of Ash) rather than unique indexes, so violations
  raise MSSQL error 2627 ("Violation of UNIQUE KEY constraint '...'")
  instead of 2601 ("Cannot insert duplicate key row ... with unique index").

  Note that MSSQL UNIQUE constraints treat NULL as a value, so at most one
  row may have a NULL `name` at a time - tests must use distinct names.
  """
  use Ecto.Migration

  def up do
    create table(:legacy_items, primary_key: false) do
      add(:id, :uuid, null: false, primary_key: true)
      add(:code, :string, null: false)
      add(:name, :string)
    end

    # Configured on the resource via `unique_index_names`.
    execute("ALTER TABLE legacy_items ADD CONSTRAINT uq_legacy_items_code UNIQUE ([code])")

    # Deliberately NOT configured on the resource, to exercise the fallback
    # error for unrecognized constraint names.
    execute("ALTER TABLE legacy_items ADD CONSTRAINT uq_legacy_items_name UNIQUE ([name])")
  end

  def down do
    drop(table(:legacy_items))
  end
end
