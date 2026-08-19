# Benchmarks the three `returning_strategy` options (:reload, :output,
# :output_into) for create / bulk-create / upsert, on both a plain table and a
# table with an enabled trigger. Reports Benchee wall-clock timing plus a
# SQL-Server-side memory report (process memory, tempdb usage, and temp-table
# creation count sampled from DMVs).
#
# Run (SQL Server must be up — see the test setup):
#
#     MIX_ENV=test TDS_PASSWORD=... mix run bench/returning_strategy.exs
#
# Optional env: TDS_HOST, TDS_PORT, BENCH_TIME (Benchee seconds, default 2),
# BENCH_N (rows per memory pass, default 1000), BENCH_BATCH (bulk size, default 100).

password = System.get_env("TDS_PASSWORD") || "YourStrong@Passw0rd"

Application.put_env(:ash_mssql, AshMssql.BenchRepo,
  username: "sa",
  password: password,
  database: "ash_mssql_test",
  hostname: System.get_env("TDS_HOST") || "localhost",
  port: String.to_integer(System.get_env("TDS_PORT") || "1433"),
  pool_size: 10,
  show_sensitive_data_on_connection_error: true,
  migration_primary_key: [name: :id, type: :binary_id]
)

defmodule AshMssql.BenchRepo do
  use AshMssql.Repo, otp_app: :ash_mssql
end

defmodule AshMssql.Bench.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered?(true)
  end
end

# One resource module per (table, strategy). All strategy variants for a table
# point at the *same* physical table, so the only difference measured is how the
# written row is fetched back. Built with `Module.create/3` to avoid repeating
# the resource body six times.
widget_body = fn table, strategy ->
  quote do
    use Ash.Resource, domain: AshMssql.Bench.Domain, data_layer: AshMssql.DataLayer

    mssql do
      table(unquote(table))
      repo(AshMssql.BenchRepo)
      returning_strategy(unquote(strategy))
    end

    actions do
      defaults([:read, :destroy, create: :*, update: :*])
    end

    attributes do
      uuid_primary_key(:id, writable?: true)
      attribute(:name, :string, public?: true, allow_nil?: false)
      attribute(:n, :integer, public?: true)
    end

    identities do
      identity(:unique_name, [:name])
    end
  end
end

for {mod, table, strategy} <- [
      {AshMssql.Bench.Reload, "bench_widgets", :reload},
      {AshMssql.Bench.Output, "bench_widgets", :output},
      {AshMssql.Bench.OutputInto, "bench_widgets", :output_into},
      {AshMssql.Bench.TrgReload, "bench_widgets_trg", :reload},
      {AshMssql.Bench.TrgOutput, "bench_widgets_trg", :output},
      {AshMssql.Bench.TrgOutputInto, "bench_widgets_trg", :output_into}
    ] do
  Module.create(mod, widget_body.(table, strategy), Macro.Env.location(__ENV__))
end

{:ok, _} = Application.ensure_all_started(:ash)
{:ok, _} = AshMssql.BenchRepo.start_link()

repo = AshMssql.BenchRepo

# --- schema setup -----------------------------------------------------------

setup_sql = fn ->
  for table <- ["bench_widgets", "bench_widgets_trg"] do
    repo.query!("IF OBJECT_ID('#{table}', 'U') IS NOT NULL DROP TABLE [#{table}];")

    repo.query!("""
    CREATE TABLE [#{table}] (
      [id] uniqueidentifier NOT NULL PRIMARY KEY,
      [name] nvarchar(255) NOT NULL,
      [n] int NULL,
      CONSTRAINT [uq_#{table}_name] UNIQUE ([name])
    );
    """)
  end

  # A no-op AFTER trigger is enough to make SQL Server reject an inline OUTPUT
  # clause (error 334) — the whole reason the other strategies exist.
  repo.query!("""
  CREATE TRIGGER [trg_bench_widgets_trg]
  ON [bench_widgets_trg]
  AFTER INSERT, UPDATE
  AS BEGIN SET NOCOUNT ON; END
  """)
end

setup_sql.()

# --- SQL Server memory sampling --------------------------------------------

sample = fn ->
  %{rows: [[proc_kb, temp_tables, tempdb_kb, total_kb]]} =
    repo.query!("""
    SELECT
      (SELECT physical_memory_in_use_kb FROM sys.dm_os_process_memory),
      (SELECT TOP 1 cntr_value FROM sys.dm_os_performance_counters
        WHERE RTRIM(counter_name) = 'Temp Tables Creation Rate'),
      (SELECT SUM(user_object_reserved_page_count + internal_object_reserved_page_count) * 8
        FROM tempdb.sys.dm_db_file_space_usage),
      (SELECT TOP 1 cntr_value FROM sys.dm_os_performance_counters
        WHERE RTRIM(counter_name) = 'Total Server Memory (KB)')
    """)

  %{process_kb: proc_kb, temp_tables: temp_tables, tempdb_kb: tempdb_kb, total_server_kb: total_kb}
end

# --- workloads --------------------------------------------------------------

uniq = fn -> System.unique_integer([:positive]) end

# The emulated (amd64-on-arm64) SQL Server occasionally drops an idle pooled
# connection between Benchee scenarios, surfacing as a one-off
# "transaction is not started" error. Retry once with a fresh connection so a
# transient blip doesn't abort the whole run. The happy path never rescues, so
# timing is unaffected.
retry = fn fun ->
  try do
    fun.()
  rescue
    _ ->
      Process.sleep(50)
      fun.()
  end
end

create_one = fn resource ->
  retry.(fn ->
    resource
    |> Ash.Changeset.for_create(:create, %{name: "w#{uniq.()}", n: 1})
    |> Ash.create!()
  end)
end

bulk = String.to_integer(System.get_env("BENCH_BATCH") || "100")

create_bulk = fn resource ->
  retry.(fn ->
    rows = for _ <- 1..bulk, do: %{name: "w#{uniq.()}", n: 1}
    Ash.bulk_create!(rows, resource, :create, return_records?: true, stop_on_error?: true)
  end)
end

# Upsert into a fixed, small key space so most operations hit the update branch.
upsert_one = fn resource ->
  retry.(fn ->
    name = "u#{rem(uniq.(), 200)}"

    resource
    |> Ash.Changeset.for_create(:create, %{name: name, n: 1})
    |> Ash.create!(upsert?: true, upsert_identity: :unique_name)
  end)
end

# --- timing (Benchee) -------------------------------------------------------

bench_time = String.to_integer(System.get_env("BENCH_TIME") || "2")

IO.puts("\n=== TIMING: plain table (bench_widgets) ===")

Benchee.run(
  %{
    "create/1 :reload" => fn -> create_one.(AshMssql.Bench.Reload) end,
    "create/1 :output" => fn -> create_one.(AshMssql.Bench.Output) end,
    "create/1 :output_into" => fn -> create_one.(AshMssql.Bench.OutputInto) end,
    "bulk_create/#{bulk} :reload" => fn -> create_bulk.(AshMssql.Bench.Reload) end,
    "bulk_create/#{bulk} :output" => fn -> create_bulk.(AshMssql.Bench.Output) end,
    "bulk_create/#{bulk} :output_into" => fn -> create_bulk.(AshMssql.Bench.OutputInto) end,
    "upsert/1 :reload" => fn -> upsert_one.(AshMssql.Bench.Reload) end,
    "upsert/1 :output" => fn -> upsert_one.(AshMssql.Bench.Output) end,
    "upsert/1 :output_into" => fn -> upsert_one.(AshMssql.Bench.OutputInto) end
  },
  time: bench_time,
  warmup: 1,
  print: [fast_warning: false]
)

IO.puts("\n=== TIMING: trigger table (bench_widgets_trg) — :output omitted (errors 334) ===")

Benchee.run(
  %{
    "create/1 :reload" => fn -> create_one.(AshMssql.Bench.TrgReload) end,
    "create/1 :output_into" => fn -> create_one.(AshMssql.Bench.TrgOutputInto) end,
    "bulk_create/#{bulk} :reload" => fn -> create_bulk.(AshMssql.Bench.TrgReload) end,
    "bulk_create/#{bulk} :output_into" => fn -> create_bulk.(AshMssql.Bench.TrgOutputInto) end
  },
  time: bench_time,
  warmup: 1,
  print: [fast_warning: false]
)

# --- SQL Server memory pass -------------------------------------------------

n = String.to_integer(System.get_env("BENCH_N") || "1000")

mem_scenarios = [
  {"plain create/1 :reload", fn -> for _ <- 1..n, do: create_one.(AshMssql.Bench.Reload) end},
  {"plain create/1 :output", fn -> for _ <- 1..n, do: create_one.(AshMssql.Bench.Output) end},
  {"plain create/1 :output_into",
   fn -> for _ <- 1..n, do: create_one.(AshMssql.Bench.OutputInto) end},
  {"trg   create/1 :reload", fn -> for _ <- 1..n, do: create_one.(AshMssql.Bench.TrgReload) end},
  {"trg   create/1 :output_into",
   fn -> for _ <- 1..n, do: create_one.(AshMssql.Bench.TrgOutputInto) end}
]

IO.puts("\n=== SQL SERVER MEMORY: #{n} single creates per strategy ===")

results =
  Enum.map(mem_scenarios, fn {label, work} ->
    before = sample.()
    {us, _} = :timer.tc(work)
    aft = sample.()

    %{
      label: label,
      ms: Float.round(us / 1000, 1),
      temp_tables: aft.temp_tables - before.temp_tables,
      tempdb_kb_delta: aft.tempdb_kb - before.tempdb_kb,
      process_kb_delta: aft.process_kb - before.process_kb,
      total_server_kb: aft.total_server_kb
    }
  end)

fmt = fn s -> String.pad_trailing(s, 30) end
col = fn v -> String.pad_leading(to_string(v), 14) end

IO.puts(
  fmt.("scenario") <>
    col.("wall_ms") <>
    col.("temp_tables") <> col.("tempdb_Δkb") <> col.("proc_Δkb") <> col.("srv_mem_kb")
)

IO.puts(String.duplicate("-", 30 + 14 * 5))

Enum.each(results, fn r ->
  IO.puts(
    fmt.(r.label) <>
      col.(r.ms) <>
      col.(r.temp_tables) <>
      col.(r.tempdb_kb_delta) <> col.(r.process_kb_delta) <> col.(r.total_server_kb)
  )
end)

IO.puts("""

Notes:
  * temp_tables = delta of the 'Temp Tables Creation Rate' perf counter (a running
    total). :output_into creates one temp table per statement; :reload/:output ~0.
  * tempdb_Δkb / proc_Δkb are instance-wide and noisy (other activity, lazy
    release); read them as trends, not exact costs. temp_tables is the clean signal.
  * :reload issues an extra SELECT round-trip; :output_into is one round-trip but
    pays the per-statement temp table. See `returning_strategy` docs.
""")

# --- cleanup ----------------------------------------------------------------

repo.query!("IF OBJECT_ID('bench_widgets', 'U') IS NOT NULL DROP TABLE [bench_widgets];")
repo.query!("IF OBJECT_ID('bench_widgets_trg', 'U') IS NOT NULL DROP TABLE [bench_widgets_trg];")
