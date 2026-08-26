defmodule AshMssql.Test.MissingTableItem do
  @moduledoc """
  Points at a table that does not exist, simulating a resource whose
  migrations were never run. Any statement raises MSSQL error 208
  ("Invalid object name 'nonexistent_items'").
  """
  use Ash.Resource,
    domain: AshMssql.Test.Domain,
    data_layer: AshMssql.DataLayer

  mssql do
    table("nonexistent_items")
    repo(AshMssql.TestRepo)
    # The missing table is the point; the generator must not create it.
    migrate?(false)
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:code, :string, public?: true)
  end
end
