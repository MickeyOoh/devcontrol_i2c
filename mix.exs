defmodule DevcontrolI2c.MixProject do
  use Mix.Project

  @app :devcontrolI2c
  @version "0.1.0"
  @source_url "https://github.com/MickeyOoh/devcontrol_i2c"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.target()),
      deps: deps(),
      test_coverage: [
        threshold: 80.0,
        ignore_modules: [
          CircuitsSim.Device.PCA9685,
          CircuitsSim.I2C.I2CDevice.CircuitsSim.Device.PCA9685,
          DevcontrolI2c.DevTable,
          DevcontrolI2c.PCA9685tbl,
        ]
      ],
      description: description(),
      #dialyzer: dailyzer(),
      docs: docs(),
      package: package(),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:host), do: ["lib", "sim_lib"]
  defp elixirc_paths(_targets), do: ["lib"]
  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      #{:fsm_diagram, "~> 0.1.0"}, 
      {:fsm_diagram, path: "../fsm_diagram"}, 
      {:circuits_i2c, "~> 2.1"},
      {:circuits_sim, "~> 0.1.2", targets: :host},
      {:ex_doc, "~> 0.35", only: [:dev, :dos], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      #{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    ]
  end

  defp description() do
    """
    Devices control for I2c bus.
    """
  end

  #defp dailyzer() do
  #  [ plt_add_apps: [:mix, :exunit], plt_file: {:no_warn, "devcontrolI2c.plt"} ]
  #end

  defp docs() do
    [
      main: "DevcontrolI2c",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [ "README.md", "CHANGELOG.md",],
      before_closing_body_tag: &before_closing_body_tag/1,
    ]
  end
  defp before_closing_body_tag(:html) do
    """
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs";
      mermaid.initialize({ startOnLoad: true });
    </script>
    """
  end
  defp before_closing_body_tag(_), do: ""

  defp package() do
    [
      files: [ "lib", "mix.exs", "test", "README.md", "LICENSE", "CHANGELOG.md"],
      licenses: ["MIT"],
      links: %{ "GitHUb" => @source_url},
    ]
  end

end
