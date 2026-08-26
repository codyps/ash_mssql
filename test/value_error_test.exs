defmodule AshMssql.Test.ValueErrorTest do
  @moduledoc """
  Covers MSSQL errors raised when a value does not fit its column:

    * 515: "Cannot insert the value NULL into column '<col>' ..." - a NULL
      reached a NOT NULL column. Ash validates allow_nil? itself, so this
      fires when the resource declares an attribute nullable while the
      column is NOT NULL (LaxItem drifts from legacy_items this way).
    * 2628: "String or binary data would be truncated in table '<t>',
      column '<col>' ..." - a string longer than the column. (Its legacy
      form 8152 carries no details and only fires on old compatibility
      levels; it maps to a generic message through the same handler.)
    * 8115: "Arithmetic overflow error converting <x> to data type <y>" -
      a numeric value exceeding the column's precision. The message names
      no column, so the error is not attributed to a field.
  """
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.LaxItem
  alias AshMssql.Test.LegacyItem
  alias AshMssql.Test.Post

  describe "null into a non-nullable column (error 515)" do
    test "creating without a value for a drifted NOT NULL column" do
      assert_raise Ash.Error.Invalid,
                   ~r/Invalid value provided for code: must not be null/,
                   fn ->
                     LaxItem
                     |> Ash.Changeset.for_create(:create, %{name: "no code"})
                     |> Ash.create!()
                   end
    end

    test "updating a drifted NOT NULL column to nil" do
      item =
        LaxItem
        |> Ash.Changeset.for_create(:create, %{code: "has-code"})
        |> Ash.create!()

      assert_raise Ash.Error.Invalid,
                   ~r/Invalid value provided for code: must not be null/,
                   fn ->
                     item
                     |> Ash.Changeset.for_update(:update, %{code: nil})
                     |> Ash.update!()
                   end
    end
  end

  describe "string truncation (error 2628)" do
    test "creating with a string longer than the column" do
      assert_raise Ash.Error.Invalid,
                   ~r/Invalid value provided for code: value is too long for the column and would be truncated/,
                   fn ->
                     LegacyItem
                     |> Ash.Changeset.for_create(:create, %{
                       code: String.duplicate("x", 300),
                       name: "long"
                     })
                     |> Ash.create!()
                   end
    end

    test "updating with a string longer than the column" do
      item =
        LegacyItem
        |> Ash.Changeset.for_create(:create, %{code: "short", name: "short"})
        |> Ash.create!()

      assert_raise Ash.Error.Invalid,
                   ~r/Invalid value provided for code: value is too long for the column and would be truncated/,
                   fn ->
                     item
                     |> Ash.Changeset.for_update(:update, %{code: String.duplicate("x", 300)})
                     |> Ash.update!()
                   end
    end
  end

  describe "arithmetic overflow (error 8115)" do
    test "creating with a decimal exceeding the column's precision" do
      assert_raise Ash.Error.Invalid,
                   ~r/value is out of range \(arithmetic overflow converting numeric to numeric\)/,
                   fn ->
                     Post
                     |> Ash.Changeset.for_create(:create, %{
                       title: "d",
                       decimal: Decimal.new("1E+30")
                     })
                     |> Ash.create!()
                   end
    end
  end
end
