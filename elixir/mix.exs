defmodule ExTailscale.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :libtailscale,
      version: @version,
      elixir: "~> 1.17",
      make_cwd: "native",
      make_clean: ["clean"],
      compilers: [:elixir_make] ++ Mix.compilers(),
      source_url: "https://github.com/Munksgaard/libtailscale/tree/elixir/elixir",
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Development dependencies
      {:elixir_make, "~> 0.9.0", runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end

  defp description do
    """
    Thin NIF-wrapper around libtailscale. Should not be used directly.
    """
  end

  defp package do
    [
      maintainers: ["Philip Munksgaard"],
      licenses: ["BSD-3-Clause"],
      links: links(),
      files: [
        "lib",
        "native/Makefile",
        "native/libtailscale_nif.c",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "priv/libtailscale/go.mod",
        "priv/libtailscale/go.sum",
        "priv/libtailscale/tailscale.c",
        "priv/libtailscale/tailscale.h",
        "priv/libtailscale/tailscale.go",
        "priv/libtailscale/Makefile",
        "priv/libtailscale/LICENSE"
      ]
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/Munksgaard/libtailscale/tree/elixir"
    }
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "priv/libtailscale/LICENSE",
        "CHANGELOG.md"
      ],
      formatters: ["html"],
      skip_undefined_reference_warnings_on: ["changelog", "CHANGELOG.md"]
    ]
  end

  defp copy_native_files do
    [
      "cmd mkdir -p priv/libtailscale",
      "cmd cp -p ../go.mod ../go.sum ../tailscale.c ../tailscale.h ../tailscale.go ../Makefile ../LICENSE priv/libtailscale"
    ]
  end

  defp aliases do
    [
      "deps.get": copy_native_files() ++ ["deps.get"]
    ]
  end
end
