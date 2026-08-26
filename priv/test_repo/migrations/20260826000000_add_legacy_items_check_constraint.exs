defmodule AshMssql.TestRepo.Migrations.AddLegacyItemsCheckConstraint do
  @moduledoc """
  Adds a hand-created CHECK constraint to legacy_items (as a DBA might),
  so tests can exercise MSSQL error 547 in its CHECK form as well as its
  FOREIGN KEY form.
  """
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE legacy_items ADD CONSTRAINT ck_legacy_items_code_not_forbidden CHECK (code <> 'forbidden')"
    )
  end

  def down do
    execute("ALTER TABLE legacy_items DROP CONSTRAINT ck_legacy_items_code_not_forbidden")
  end
end
