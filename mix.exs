defmodule ElixirYtBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_yt_bot,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {AudioBot, {}},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {
        :nostrum,
        git: "https://github.com/Kraigie/nostrum.git",
        ref: "b2b660b2cf5212fd6b6a581d1626e135ac868053"
        # using this specific ref as it's the one that works lol
      }
    ]
  end
end
