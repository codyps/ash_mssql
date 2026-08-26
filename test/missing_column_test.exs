defmodule AshMssql.Test.MissingColumnTest do
  @moduledoc """
  Covers MSSQL error 207 ("Invalid column name '...'") - raised whenever a
  statement references a column that does not exist, typically because the
  database schema drifted behind the resource definition.

  PhantomItem defines an `extra` attribute with no backing column on
  `legacy_items`, so every operation that touches `extra` raises 207. Reads,
  filters, sorts, creates, upserts, updates, and bulk creates all surface it.
  """
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.LegacyItem
  alias AshMssql.Test.PhantomItem

  require Ash.Query

  @error_message ~r/Column "extra" does not exist on table "legacy_items".*out of date/s

  test "reading a resource whose attribute has no backing column" do
    error = assert_raise(Ash.Error.Framework, @error_message, fn -> Ash.read!(PhantomItem) end)

    assert [
             %AshMssql.Error.MissingColumn{
               resource: PhantomItem,
               table: "legacy_items",
               column: "extra"
             }
           ] = error.errors
  end

  test "filtering on an attribute with no backing column" do
    assert_raise Ash.Error.Framework, @error_message, fn ->
      PhantomItem
      |> Ash.Query.select([:id])
      |> Ash.Query.filter(extra == "x")
      |> Ash.read!()
    end
  end

  test "sorting on an attribute with no backing column" do
    assert_raise Ash.Error.Framework, @error_message, fn ->
      PhantomItem
      |> Ash.Query.select([:id])
      |> Ash.Query.sort(:extra)
      |> Ash.read!()
    end
  end

  test "creating with an attribute that has no backing column" do
    assert_raise Ash.Error.Framework, @error_message, fn ->
      PhantomItem
      |> Ash.Changeset.for_create(:create, %{code: "p1", extra: "x"})
      |> Ash.create!()
    end
  end

  test "upserting with an attribute that has no backing column" do
    assert_raise Ash.Error.Framework, @error_message, fn ->
      PhantomItem
      |> Ash.Changeset.for_create(:create, %{code: "p2", extra: "x"})
      |> Ash.create!(upsert?: true)
    end
  end

  test "bulk creating with an attribute that has no backing column" do
    assert_raise Ash.Error.Framework, @error_message, fn ->
      Ash.bulk_create!([%{code: "p3", extra: "x"}], PhantomItem, :create,
        return_errors?: true,
        stop_on_error?: true
      )
    end
  end

  test "aggregating with a filter on an attribute that has no backing column" do
    assert_raise Ash.Error.Framework, @error_message, fn ->
      PhantomItem
      |> Ash.Query.filter(extra == "x")
      |> Ash.count!()
    end
  end

  test "updating an attribute that has no backing column" do
    # Seed through LegacyItem (same table, no phantom attribute), then read
    # the record as a PhantomItem while avoiding the missing column.
    LegacyItem
    |> Ash.Changeset.for_create(:create, %{code: "seed", name: "seed"})
    |> Ash.create!()

    record =
      PhantomItem
      |> Ash.Query.select([:id, :code, :name])
      |> Ash.read_one!()

    assert_raise Ash.Error.Framework, @error_message, fn ->
      record
      |> Ash.Changeset.for_update(:update, %{extra: "x"})
      |> Ash.update!()
    end
  end
end
