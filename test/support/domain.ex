defmodule AshMssql.Test.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshMssql.Test.Post)
    resource(AshMssql.Test.Comment)
    resource(AshMssql.Test.IntegerPost)
    resource(AshMssql.Test.Rating)
    resource(AshMssql.Test.PostLink)
    resource(AshMssql.Test.PostView)
    resource(AshMssql.Test.Author)
    resource(AshMssql.Test.Profile)
    resource(AshMssql.Test.User)
    resource(AshMssql.Test.Account)
    resource(AshMssql.Test.Organization)
    resource(AshMssql.Test.Manager)
    resource(AshMssql.Test.ReplicaPost)
    resource(AshMssql.Test.LegacyItem)
  end

  authorization do
    authorize(:when_requested)
  end
end
