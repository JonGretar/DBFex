defmodule DBF.MixProject do
  use Mix.Project

  def project do
    [
      app: :dbf_ex,
      version: "0.5.0",
      elixir: "~> 1.15",
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
    Read FoxBase, dBASE III/IV, FoxPro, and Visual FoxPro DBF files in Elixir,
    including DBT and FPT memo data.
    """
  end

  def docs do
    [
      main: "DBF",
      extras: [
        "CHANGELOG.md",
        "docs/Architecture.md",
        "docs/DBF-Format.md"
      ],
      groups_for_extras: [
        "Release notes": [
          "CHANGELOG.md"
        ],
        "Architecture and formats": [
          "docs/Architecture.md",
          "docs/DBF-Format.md"
        ]
      ],
      before_closing_body_tag: &mermaid_script/1,
      skip_code_autolink_to: &hidden_internal_module?/1
    ]
  end

  defp mermaid_script(:html) do
    ~S"""
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp mermaid_script(_format), do: ""

  defp hidden_internal_module?(reference) do
    Enum.any?(
      ~w(
        DBF.DatabaseError.from_internal
        DBF.Error
        DBF.FieldDescriptorLayout
        DBF.FormatProfile
        DBF.Header
        DBF.Memo
        DBF.Memo.FPT
        DBF.Opening
        DBF.Record
        DBF.RecordReader
        DBF.Resource
        DBF.Schema
        DBF.TextDecoder
        DBF.ValueDecoder
      ),
      &(reference == &1 or String.starts_with?(reference, &1 <> ".") or
          String.starts_with?(reference, &1 <> "/"))
    )
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
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"],
      maintainers: ["Jón Grétar Borgþórsson"],
      licenses: ["MIT"],
      source_url: "https://github.com/JonGretar/DBFex",
      links: %{"GitHub" => "https://github.com/JonGretar/DBFex"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:decimal, "~> 3.1"},
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
