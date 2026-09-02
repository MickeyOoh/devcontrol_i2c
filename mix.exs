defmodule DevcontrolI2c.MixProject do
  use Mix.Project

  @app :i2c_control
  @version "0.1.0"
  @source_url ""

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.target()),
      deps: deps()
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
      {:fsm_diagram, "~> 0.1.0"}, 
      {:circuits_i2c, "~> 2.1"},
      {:circuits_sim, "~> 0.1.2", targets: :host},
    ]
  end
end
