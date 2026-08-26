defmodule AshMssql.Test.LegacyItem do
  @moduledoc """
  Backed by a table whose uniqueness comes from table-level UNIQUE KEY
  constraints (created outside of Ash-generated migrations) rather than
  unique indexes. Violations raise MSSQL error 2627
  ("Violation of UNIQUE KEY constraint '...'") instead of 2601.
  """
  use Ash.Resource,
    domain: AshMssql.Test.Domain,
    data_layer: AshMssql.DataLayer

  mssql do
    table("legacy_items")
    repo(AshMssql.TestRepo)
    # The table is created by a hand-written migration (UNIQUE KEY
    # constraints); keep the generator from trying to manage it.
    migrate?(false)

    unique_index_names([
      {[:code], "uq_legacy_items_code", "code has already been taken"}
    ])
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:code, :string, allow_nil?: false, public?: true)
    attribute(:name, :string, public?: true)
  end
end
