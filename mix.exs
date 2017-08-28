defmodule TypeStruct.Mixfile do
  use Mix.Project

  def project do
    [app: :type_struct,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     package: package(),
     name: "TypeStruct",
     docs: [main: "TypeStruct"],
     description: "A better way to define structs and their types."]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    []
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:ex_doc, "~> 0.15", only: :dev, runtime: false}]
  end

  def package do
    [name: :type_struct,
     maintainers: ["Akio Burns"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/net/type_struct"}]
  end
end
