defmodule AshMssql.Test.PostOutputInto do
  @moduledoc """
  Maps the `posts` table with `returning_strategy :output_into`, so the trigger
  test can exercise the `OUTPUT ... INTO` path (the other trigger-safe strategy)
  alongside the default `:reload`.
  """
  use Ash.Resource,
    domain: AshMssql.Test.Domain,
    data_layer: AshMssql.DataLayer

  mssql do
    table "posts"
    repo AshMssql.TestRepo
    returning_strategy :output_into
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:title, :string, public?: true)
    attribute(:score, :integer, public?: true)
    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end
end
