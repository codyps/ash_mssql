defmodule AshMssql.TriggerReturningTest do
  @moduledoc """
  Regression coverage for the SQL Server rule that an inline `OUTPUT` clause is
  rejected on a table with enabled triggers (error 334). The default `:reload`
  strategy and `:output_into` must both work there; plain inline `OUTPUT` must
  not — which is exactly what those strategies exist to avoid.
  """
  use AshMssql.RepoCase, async: false

  alias AshMssql.Test.{Post, PostOutputInto}
  alias AshMssql.TestRepo

  setup do
    # Create a no-op AFTER trigger on `posts` for the duration of this test. The
    # sandbox transaction rolls it back afterward, and CREATE TRIGGER is its own
    # batch via query!, satisfying "must be the only statement in the batch".
    TestRepo.query!("""
    CREATE TRIGGER [trg_posts_returning_test]
    ON [posts]
    AFTER INSERT, UPDATE
    AS BEGIN SET NOCOUNT ON; END
    """)

    :ok
  end

  test "default :reload create succeeds on a table with triggers" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "trig"})
      |> Ash.create!()

    assert %Post{title: "trig"} = post
    assert post.id
  end

  test ":output_into create succeeds on a table with triggers" do
    post =
      PostOutputInto
      |> Ash.Changeset.for_create(:create, %{title: "trig-oi", score: 7})
      |> Ash.create!()

    assert %PostOutputInto{title: "trig-oi", score: 7} = post
    assert post.id
  end

  test "inline OUTPUT (the pre-fix behavior) fails on a table with triggers" do
    # This is what Ecto's `:returning` emits and what the strategies avoid.
    entry = %{
      id: Ash.UUID.generate(),
      title: "boom",
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    error =
      assert_raise Tds.Error, fn ->
        TestRepo.insert_all(Post, [entry], returning: [:id])
      end

    assert error.mssql.number == 334
  end
end
