defmodule DBF.MixProject do
  use Mix.Project

  def project do
    [
      app: :dbf,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      package: package(),
      description: description(),
      licenses: ["MIT"],
      docs: docs(),
      deps: deps()
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
      files: ["lib", "mix.exs", "README.md"],
      maintainers: ["Jón Grétar Borgþórsson"],
      licenses: ["MIT"],
      source_url: "https://github.com/JonGretar/DBFex",
      links: %{"GitHub" => "https://github.com/JonGretar/DBFex"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
