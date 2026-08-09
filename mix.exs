defmodule Faviconic.MixProject do
  use Mix.Project

  def project do
    [
      app: :faviconic,
      version: "0.3.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/bonfire-networks/faviconic"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # HTTP Client
      {:req, "~> 0.7"},
      # HTML Parser
      {:floki, "~> 0.32"},
      # error handling
      {:untangle, "~> 0.5"},
      {:process_tree, "~> 0.3.0"},
      # For testing
      {:mock, "~> 0.3.0", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description do
    "Fetch a favicon from URL, with multiple fallbacks"
  end

  defp package() do
    [
      maintainers: ["Bonfire Networks"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bonfire-networks/faviconic"}
    ]
  end
end
