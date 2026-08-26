defmodule AshMssql.Error.MissingTable do
  @moduledoc """
  Raised when a statement references a table that does not exist in the
  database (MSSQL error 208, "Invalid object name '...'").

  This usually means the resource's migrations were never generated or run.
  """

  use Splode.Error, fields: [:resource, :table, :raw_message], class: :framework

  def message(%{resource: resource, table: table, raw_message: raw_message}) do
    """
    #{describe(table)} (referenced while acting on #{inspect(resource)}).

    Raw error: #{raw_message}

    This usually means the resource's migrations were never generated or run:

        mix ash.codegen <describe_your_changes>
        mix ash_mssql.migrate
    """
  end

  defp describe(nil), do: "Statement referenced a table that does not exist"
  defp describe(table), do: "Table \"#{table}\" does not exist"
end
