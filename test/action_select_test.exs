defmodule AshMssql.ActionSelectTest do
  @moduledoc false
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.{IntegerPost, Post}

  import Ash.Expr
  require Ash.Query

  defp capture_queries(fun) do
    ref = make_ref()
    parent = self()
    handler_id = {__MODULE__, ref}

    :telemetry.attach(
      handler_id,
      [:ash_mssql, :test_repo, :query],
      fn _event, _measurements, metadata, _config ->
        send(parent, {ref, metadata.query})
      end,
      nil
    )

    try do
      result = fun.()
      {result, drain_queries(ref)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(ref, acc \\ []) do
    receive do
      {^ref, query} -> drain_queries(ref, [query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # With the default `:reload` returning strategy, inserts/updates/upserts do not
  # use an inline `OUTPUT` clause (SQL Server forbids it on tables with
  # triggers). The written rows are re-selected afterwards, so column-trimming
  # assertions target that reload `SELECT` list. Only the SELECT list — columns
  # must not accidentally match the WHERE clause (`WHERE s0.[id] = ...`).
  defp reload_select_clause(queries) do
    queries
    |> Enum.find(fn query ->
      String.starts_with?(query, "SELECT") and String.contains?(query, "posts")
    end)
    |> case do
      nil -> flunk("expected a reload SELECT against posts, got: #{inspect(queries)}")
      query -> query |> String.split(" FROM ") |> hd()
    end
  end

  test "bulk create with a select only returns the selected fields" do
    {result, queries} =
      capture_queries(fn ->
        Ash.bulk_create!(
          [%{title: "fred", score: 3}, %{title: "george", score: 4}],
          Post,
          :create_barebones,
          return_records?: true,
          select: [:title]
        )
      end)

    assert [%{title: "fred"}, %{title: "george"}] =
             Enum.sort_by(result.records, & &1.title)

    select_clause = reload_select_clause(queries)

    assert select_clause =~ "[id]"
    assert select_clause =~ "[title]"
    refute select_clause =~ "[score]"
    refute select_clause =~ "[stuff]"
  end

  test "bulk create without a select returns the default-selected fields as full records" do
    {result, queries} =
      capture_queries(fn ->
        Ash.bulk_create!([%{title: "fred", score: 3}], Post, :create_barebones,
          return_records?: true
        )
      end)

    assert [%{title: "fred", score: 3}] = result.records

    # No explicit select means all default-selected attributes are reloaded.
    select_clause = reload_select_clause(queries)
    assert select_clause =~ "[score]"
  end

  test "creates with database-generated integer primary keys still return real values" do
    post =
      IntegerPost
      |> Ash.Changeset.for_create(:create, %{title: "fred"})
      |> Ash.create!()

    assert %{title: "fred"} = post
    assert is_integer(post.id)
  end

  test "single create with a changeset select only returns the selected fields" do
    {post, queries} =
      capture_queries(fn ->
        Post
        |> Ash.Changeset.for_create(:create_barebones, %{title: "fred", score: 5})
        |> Ash.Changeset.select([:title])
        |> Ash.create!()
      end)

    assert %{title: "fred", score: %Ash.NotLoaded{}} = post

    select_clause = reload_select_clause(queries)

    assert select_clause =~ "[title]"
    refute select_clause =~ "[score]"
  end

  test "non-default-selected attributes are not returned, but always_select? ones are" do
    {post, queries} =
      capture_queries(fn ->
        Post
        |> Ash.Changeset.for_create(:create_barebones, %{
          title: "fred",
          uniq_custom_one: "not selected by default",
          uniq_custom_two: "always selected"
        })
        |> Ash.create!()
      end)

    # uniq_custom_one is select_by_default?: false and wasn't requested, so it
    # must come back as NotLoaded — not as a loaded nil.
    assert %Ash.NotLoaded{} = post.uniq_custom_one

    # uniq_custom_two is always_select?: true. Ash core's NotLoaded masking
    # assumes the data layer loaded it, so the data layer must return it even
    # though it isn't selected by default.
    assert post.uniq_custom_two == "always selected"

    select_clause = reload_select_clause(queries)
    refute select_clause =~ "[uniq_custom_one]"
    assert select_clause =~ "[uniq_custom_two]"
  end

  test "upserts trim the reload SELECT to the action select plus the upsert keys" do
    {post, queries} =
      capture_queries(fn ->
        Post
        |> Ash.Changeset.for_create(:create_barebones, %{
          title: "fred",
          score: 3,
          uniq_one: "one",
          uniq_two: "two"
        })
        |> Ash.Changeset.select([:title])
        |> Ash.create!(upsert?: true, upsert_identity: :uniq_one_and_two)
      end)

    assert %{title: "fred", score: %Ash.NotLoaded{}} = post

    merge = Enum.find(queries, &String.starts_with?(&1, "MERGE"))
    assert merge, "expected a MERGE against posts, got: #{inspect(queries)}"

    select_clause = reload_select_clause(queries)

    assert select_clause =~ "[id]"
    assert select_clause =~ "[title]"
    # The upsert keys stay selected so results can be correlated back to their
    # changesets.
    assert select_clause =~ "[uniq_one]"
    assert select_clause =~ "[uniq_two]"
    refute select_clause =~ "[score]"
    refute select_clause =~ "[stuff]"
  end

  test "updates reload fields the changeset data doesn't carry" do
    _post =
      Post
      |> Ash.Changeset.for_create(:create_barebones, %{
        title: "fred",
        uniq_custom_two: "always selected"
      })
      |> Ash.create!()

    # Fetch a copy where everything but the pkey is NotLoaded, then update it.
    # The data layer must reload whatever the changeset can't provide itself:
    # regular action_select fields (title) and always_select? attributes
    # (uniq_custom_two) alike.
    [narrow] = Ash.read!(Ash.Query.select(Post, [:id]))

    updated =
      narrow
      |> Ash.Changeset.for_update(:update, %{score: 7})
      |> Ash.update!()

    assert updated.score == 7
    assert updated.title == "fred"
    assert updated.uniq_custom_two == "always selected"
  end

  test "update with a changeset select trims the reload query" do
    post =
      Post
      |> Ash.Changeset.for_create(:create_barebones, %{title: "fred"})
      |> Ash.create!()

    {updated, queries} =
      capture_queries(fn ->
        post
        |> Ash.Changeset.for_update(:update, %{score: 9})
        |> Ash.Changeset.select([:title])
        |> Ash.update!()
      end)

    # score was written but not selected, so ash core masks it.
    assert %Ash.NotLoaded{} = updated.score
    assert updated.title == "fred"

    select_clause = reload_select_clause(queries)

    assert select_clause =~ "[title]"
    refute select_clause =~ "[stuff]"
    refute select_clause =~ "[category]"
  end

  test "single create through an action with changes still returns full records" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "fred", score: 5})
      |> Ash.create!()

    assert %{title: "fred", score: 5} = post
  end

  test "updates still return correct values with action_select in play" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "fred", score: 1})
      |> Ash.create!()

    updated =
      post
      |> Ash.Changeset.for_update(:update, %{score: 2})
      |> Ash.update!()

    assert %{title: "fred", score: 2} = updated
  end

  test "atomic updates still reload atomic values" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "fred", score: 1})
      |> Ash.create!()

    assert %{score: 3} = Post.increment_score!(post, 2)
  end

  test "atomic upserts still return correct values with a select" do
    post =
      Post
      |> Ash.Changeset.for_create(:create_barebones, %{
        title: "fred",
        score: 1,
        uniq_one: "one",
        uniq_two: "two"
      })
      |> Ash.create!()

    upserted =
      Post
      |> Ash.Changeset.for_create(
        :create_barebones,
        %{title: "fred", uniq_one: "one", uniq_two: "two"},
        upsert?: true,
        upsert_identity: :uniq_one_and_two
      )
      |> Ash.Changeset.atomic_update(:score, expr((score || 0) + 10))
      |> Ash.Changeset.select([:title, :score])
      |> Ash.create!()

    assert upserted.id == post.id
    assert upserted.score == 11
    assert upserted.title == "fred"
  end
end
