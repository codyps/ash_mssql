defmodule AshMssql.Test.MissingTableTest do
  @moduledoc """
  Covers MSSQL error 208 ("Invalid object name '...'") - raised when a
  statement references a table that does not exist, typically because the
  resource's migrations were never run.

  MissingTableItem points at a table that does not exist.
  """
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.MissingTableItem

  @error_message ~r/Table "nonexistent_items" does not exist.*migrations were never generated or run/s

  test "reading a resource whose table does not exist" do
    error =
      assert_raise(Ash.Error.Framework, @error_message, fn -> Ash.read!(MissingTableItem) end)

    assert [
             %AshMssql.Error.MissingTable{
               resource: MissingTableItem,
               table: "nonexistent_items"
             }
           ] = error.errors
  end

  test "creating into a table that does not exist" do
    assert_raise Ash.Error.Framework, @error_message, fn ->
      MissingTableItem
      |> Ash.Changeset.for_create(:create, %{code: "x"})
      |> Ash.create!()
    end
  end
end
