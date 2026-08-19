defmodule AshMssql.MixProject do
  use Mix.Project

  @description """
  The MSSQL data layer for Ash Framework.
  """

  @version "0.1.0-dev"

  def project do
    [
      app: :ash_mssql,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      description: @description,
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test,
        "test.create": :test,
        "test.migrate": :test,
        "test.rollback": :test,
        "test.check_migrations": :test,
        "test.drop": :test,
        "test.generate_migrations": :test,
        "test.reset": :test
      ],
      dialyzer: [
        plt_add_apps: [:ecto, :ash, :mix]
      ],
      docs: &docs/0,
      aliases: aliases(),
      package: package(),
      source_url: "https://github.com/ash-project/ash_mssql",
      homepage_url: "https://github.com/ash-project/ash_mssql",
      consolidate_protocols: Mix.env() != :test
    ]
  end

  if Mix.env() == :test do
    def application do
      [
        mod: {AshMssql.TestApp, []}
      ]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: :ash_mssql,
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*
      CHANGELOG* documentation usage-rules.md),
      links: %{
        GitHub: "https://github.com/ash-project/ash_mssql"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      logo: "logos/small-logo.png",
      extras: [
        {"README.md", title: "Home"},
        "documentation/tutorials/getting-started-with-ash-mssql.md",
        "documentation/topics/about-ash-mssql/what-is-ash-mssql.md",
        "documentation/topics/resources/references.md",
        "documentation/topics/resources/polymorphic-resources.md",
        "documentation/topics/development/migrations-and-tasks.md",
        "documentation/topics/development/testing.md",
        "documentation/topics/advanced/expressions.md",
        "documentation/topics/advanced/manual-relationships.md",
        {"documentation/dsls/DSL-AshMssql.DataLayer.md",
         search_data: Spark.Docs.search_data_for(AshMssql.DataLayer)},
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Tutorials: [
          ~r'documentation/tutorials'
        ],
        "How To": ~r'documentation/how_to',
        Topics: ~r'documentation/topics',
        DSLs: ~r'documentation/dsls',
        "About AshMssql": [
          "CHANGELOG.md"
        ]
      ],
      groups_for_modules: [
        AshMssql: [
          AshMssql,
          AshMssql.Repo,
          AshMssql.DataLayer
        ],
        Utilities: [
          AshMssql.ManualRelationship
        ],
        Introspection: [
          AshMssql.DataLayer.Info,
          AshMssql.CustomExtension,
          AshMssql.CustomIndex,
          AshMssql.Reference,
          AshMssql.Statement
        ],
        Types: [
          AshMssql.Type
        ],
        Expressions: [
          AshMssql.Functions.Fragment,
          AshMssql.Functions.Like
        ],
        Internals: ~r/.*/
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.12"},
      {:tds, "~> 2.3"},
      {:ecto, "~> 3.12"},
      {:jason, "~> 1.0"},
      {:ash, ash_version("~> 3.19")},
      {:picosat_elixir, "~> 0.2"},
      {:ash_sql, ash_sql_version(">= 0.6.0 and < 0.7.0")},
      {:benchee, "~> 1.3", only: [:dev, :test]},
      {:igniter, "~> 0.5", only: [:dev, :test]},
      {:git_ops, "~> 2.5", only: [:dev, :test]},
      {:ex_doc, "~> 0.22", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.14", only: [:dev, :test]},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil ->
        default_version

      "local" ->
        [path: "../ash", override: true]

      "main" ->
        [git: "https://github.com/ash-project/ash.git"]

      version when is_binary(version) ->
        "~> #{version}"

      version ->
        version
    end
  end

  defp ash_sql_version(default_version) do
    case System.get_env("ASH_SQL_VERSION") do
      nil ->
        default_version

      "local" ->
        [path: "../ash_sql", override: true]

      "main" ->
        [git: "https://github.com/ash-project/ash_sql.git"]

      version when is_binary(version) ->
        "~> #{version}"

      version ->
        version
    end
  end

  defp aliases do
    [
      sobelow:
        "sobelow --skip -i Config.Secrets --ignore-files lib/migration_generator/migration_generator.ex",
      credo: "credo --strict",
      docs: [
        "spark.cheat_sheets",
        "docs",
        "spark.replace_doc_links"
      ],
      "spark.formatter": "spark.formatter --extensions AshMssql.DataLayer",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshMssql.DataLayer",
      "spark.cheat_sheets_in_search":
        "spark.cheat_sheets_in_search --extensions AshMssql.DataLayer",
      "test.generate_migrations": "ash_mssql.generate_migrations",
      "test.check_migrations": "ash_mssql.generate_migrations --check",
      "test.migrate": "ash_mssql.migrate",
      "test.rollback": "ash_mssql.rollback",
      "test.create": "ash_mssql.create",
      "test.reset": ["test.drop", "test.create", "test.migrate"],
      "test.drop": "ash_mssql.drop"
    ]
  end
end
