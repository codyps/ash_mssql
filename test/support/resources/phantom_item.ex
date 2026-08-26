defmodule AshMssql.Test.PhantomItem do
  @moduledoc """
  Points at the `legacy_items` table but defines an `extra` attribute whose
  column does not exist, simulating a database schema that has drifted behind
  the resource definition (e.g. unrun migrations). Any statement referencing
  `extra` raises MSSQL error 207 ("Invalid column name 'extra'").
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
    attribute(:code, :string, allow_nil?: false, public?: true)
    attribute(:name, :string, public?: true)
    attribute(:extra, :string, public?: true)
  end
end
