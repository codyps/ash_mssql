defmodule AshMssql.Test.LaxItem do
  @moduledoc """
  Points at the `legacy_items` table but declares `code` as nullable even
  though the column is NOT NULL, simulating nullability drift between the
  resource and the database. Creating a record without `code` passes Ash's
  own validation and raises MSSQL error 515 ("Cannot insert the value NULL
  into column ...").
  """
  use Ash.Resource,
    domain: AshMssql.Test.Domain,
    data_layer: AshMssql.DataLayer

  mssql do
    table("legacy_items")
    repo(AshMssql.TestRepo)
    # The table belongs to AshMssql.Test.LegacyItem; this resource's schema
    # drift is intentional and must not be "fixed" by the generator.
    migrate?(false)
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:code, :string, public?: true)
    attribute(:name, :string, public?: true)
  end
end
