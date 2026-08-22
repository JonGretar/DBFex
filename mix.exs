defmodule DBF.MixProject do
  use Mix.Project

  def project do
    [
      app: :dbf_ex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      package: package(),
      description: description(),
      docs: docs(),
      deps: deps(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/#{Mix.env()}.plt"},
        plt_add_apps: [:ex_unit, :mix]
      ],
      preferred_cli_env: [precommit: :test],
      aliases: aliases()
    ]
  end

  defp description do
    """
    Read DBASE files in Elixir.

    At the moment it only supports read.
    """
  end

  def docs do
    [
      main: "DBF"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    # These are the default files included in the package
    [
      name: "dbf_ex",
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md"],
      maintainers: ["Jón Grétar Borgþórsson"],
      licenses: ["MIT"],
      source_url: "https://github.com/JonGretar/DBFex",
      links: %{"GitHub" => "https://github.com/JonGretar/DBFex"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test",
        "dialyzer",
        "credo --strict"
      ]
    ]
  end
end
