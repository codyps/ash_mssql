defmodule AshMssql.Error.MissingColumn do
  @moduledoc """
  Raised when a statement references a column that does not exist in the
  database (MSSQL error 207, "Invalid column name '...'").

  This usually means the database schema has drifted behind the resource
  definition - an attribute was added to the resource but the corresponding
  migration was never generated or run.
  """

  use Splode.Error, fields: [:resource, :table, :column, :raw_message], class: :framework

  def message(%{resource: resource, table: table, column: column, raw_message: raw_message}) do
    """
    #{describe(column, table)} (referenced while acting on #{inspect(resource)}).

    Raw error: #{raw_message}

    This usually means the database schema is out of date with the resource
    definition. If the attribute was recently added to the resource, generate
    and run migrations:

        mix ash.codegen <describe_your_changes>
        mix ash_mssql.migrate
    """
  end

  defp describe(nil, nil), do: "Statement referenced a column that does not exist"

  defp describe(nil, table),
    do: "Statement referenced a column that does not exist on table \"#{table}\""

  defp describe(column, nil), do: "Column \"#{column}\" does not exist"

  defp describe(column, table),
    do: "Column \"#{column}\" does not exist on table \"#{table}\""
end
