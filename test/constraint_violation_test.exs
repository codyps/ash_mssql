defmodule AshMssql.Test.ConstraintViolationTest do
  @moduledoc """
  Covers the two duplicate-key message shapes MSSQL can raise, on both
  inserts and updates:

    * 2627: "Violation of UNIQUE KEY constraint '<name>'" - table-level
      UNIQUE KEY constraints (LegacyItem's table uses these)
    * 2601: "Cannot insert duplicate key row in object '<table>' with
      unique index '<name>'" - unique indexes (Post's identities use these)
  """
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.LegacyItem
  alias AshMssql.Test.Post

  describe "UNIQUE KEY constraint violations (error 2627)" do
    test "create violating a configured constraint raises an error on the configured field" do
      LegacyItem
      |> Ash.Changeset.for_create(:create, %{code: "abc", name: "first"})
      |> Ash.create!()

      assert_raise Ash.Error.Invalid,
                   ~r/Invalid value provided for code: code has already been taken/,
                   fn ->
                     LegacyItem
                     |> Ash.Changeset.for_create(:create, %{code: "abc", name: "second"})
                     |> Ash.create!()
                   end
    end

    test "update violating a configured constraint raises an error on the configured field" do
      LegacyItem
      |> Ash.Changeset.for_create(:create, %{code: "abc", name: "first"})
      |> Ash.create!()

      second =
        LegacyItem
        |> Ash.Changeset.for_create(:create, %{code: "def", name: "second"})
        |> Ash.create!()

      assert_raise Ash.Error.Invalid,
                   ~r/Invalid value provided for code: code has already been taken/,
                   fn ->
                     second
                     |> Ash.Changeset.for_update(:update, %{code: "abc"})
                     |> Ash.update!()
                   end
    end

    test "bulk create violating a configured constraint raises an error on the configured field" do
      assert_raise Ash.Error.Invalid,
                   ~r/Invalid value provided for code: code has already been taken/,
                   fn ->
                     Ash.bulk_create!(
                       [
                         %{code: "abc", name: "first"},
                         %{code: "abc", name: "second"}
                       ],
                       LegacyItem,
                       :create,
                       return_errors?: true,
                       stop_on_error?: true
                     )
                   end
    end

    test "violating an unconfigured constraint still produces a duplicate-key error" do
      LegacyItem
      |> Ash.Changeset.for_create(:create, %{code: "abc", name: "same"})
      |> Ash.create!()

      # `uq_legacy_items_name` is not declared in `unique_index_names`, so the
      # error falls back to the primary key fields with a generic message
      # rather than leaking a raw Tds.Error.
      assert_raise Ash.Error.Invalid,
                   ~r/Invalid value provided for id: has already been taken/,
                   fn ->
                     LegacyItem
                     |> Ash.Changeset.for_create(:create, %{code: "def", name: "same"})
                     |> Ash.create!()
                   end
    end
  end

  describe "CHECK constraint violations (error 547)" do
    test "create violating a check constraint names the constraint" do
      assert_raise Ash.Error.Invalid,
                   ~r/violates check constraint "ck_legacy_items_code_not_forbidden"/,
                   fn ->
                     LegacyItem
                     |> Ash.Changeset.for_create(:create, %{code: "forbidden", name: "check"})
                     |> Ash.create!()
                   end
    end

    test "update violating a check constraint names the constraint" do
      item =
        LegacyItem
        |> Ash.Changeset.for_create(:create, %{code: "allowed", name: "check-update"})
        |> Ash.create!()

      assert_raise Ash.Error.Invalid,
                   ~r/violates check constraint "ck_legacy_items_code_not_forbidden"/,
                   fn ->
                     item
                     |> Ash.Changeset.for_update(:update, %{code: "forbidden"})
                     |> Ash.update!()
                   end
    end
  end

  describe "foreign key violations (error 547)" do
    test "create referencing a missing parent reports the referencing field" do
      # The comments -> posts foreign key is named via the `references` DSL
      # ("special_name_fkey"), which the error handler resolves back to the
      # source attribute.
      assert_raise Ash.Error.Invalid,
                   ~r/Invalid value provided for post_id: does not exist/,
                   fn ->
                     AshMssql.Test.Comment
                     |> Ash.Changeset.for_create(:create, %{title: "orphan"})
                     |> Ash.Changeset.force_change_attribute(:post_id, Ash.UUID.generate())
                     |> Ash.create!()
                   end
    end

    test "destroying a record that other records still reference" do
      # Organization has no back-relation to Post, so this arrives as an
      # Ecto.ConstraintError from repo.delete rather than a Tds.Error.
      org =
        AshMssql.Test.Organization
        |> Ash.Changeset.for_create(:create, %{name: "org"})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "child", organization_id: org.id})
      |> Ash.create!()

      assert_raise Ash.Error.Invalid, ~r/would leave records behind/, fn ->
        Ash.destroy!(org)
      end
    end
  end

  describe "unique index violations (error 2601)" do
    test "update violating an identity's unique index uses the identity's message" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "a", uniq_one: "one", uniq_two: "two"})
      |> Ash.create!()

      other =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "b", uniq_one: "three", uniq_two: "four"})
        |> Ash.create!()

      assert_raise Ash.Error.Invalid,
                   ~r/Invalid value provided for uniq_one: uniq_one_and_two message/,
                   fn ->
                     other
                     |> Ash.Changeset.for_update(:update, %{uniq_one: "one", uniq_two: "two"})
                     |> Ash.update!()
                   end
    end
  end
end
