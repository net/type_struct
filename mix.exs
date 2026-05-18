defmodule TypeStruct.MixProject do
  use Mix.Project

  def project do
    [
      app: :type_struct,
      version: "1.0.0",
      elixir: ">= 1.14.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      name: "TypeStruct",
      source_url: "https://github.com/net/type_struct",
      docs: [
        main: "TypeStruct",
        source_ref: "v1.0.0",
        extras: ["README.md"]
      ],
      description: "Define Elixir structs and their types together."
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: :type_struct,
      maintainers: ["Akio Burns"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/net/type_struct"}
    ]
  end
end
