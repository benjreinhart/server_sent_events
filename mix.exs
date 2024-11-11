defmodule ServerSentEvents.MixProject do
  use Mix.Project

  @github_repo_url "https://github.com/benjreinhart/server_sent_events"

  @description "Efficient and fully spec conformant Server Sent Event parser"

  def project do
    [
      app: :server_sent_events,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      name: "Server Sent Events",
      description: @description,
      source_url: @github_repo_url,
      homepage_url: @github_repo_url,
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def description do
    @description
  end

  def package do
    [
      maintainers: ["Ben Reinhart"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @github_repo_url
      }
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
