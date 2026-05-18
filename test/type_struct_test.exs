defmodule TypeStructTest do
  use ExUnit.Case
  doctest TypeStruct

  defp unique_module(name) do
    Module.concat([__MODULE__, Generated, "#{name}#{System.unique_integer([:positive])}"])
  end

  defp compile_source(source) do
    previous_options = Code.compiler_options()

    modules =
      try do
        Code.compiler_options(debug_info: true, ignore_module_conflict: true)
        Code.compile_string(source)
      after
        Code.compiler_options(previous_options)
      end

    on_exit(fn ->
      for {module, _bytecode} <- modules do
        :code.purge(module)
        :code.delete(module)
      end
    end)

    modules
  end

  defp fetch_types!(modules, module) do
    {_module, bytecode} = Enum.find(modules, &(elem(&1, 0) == module))
    {:ok, types} = Code.Typespec.fetch_types(bytecode)
    strip_numbers(types)
  end

  defp has_type?(term, name) do
    contains?(term, fn
      {:type, _, ^name, _} -> true
      _ -> false
    end)
  end

  defp has_remote_type?(term, module, name) do
    contains?(term, fn
      {:remote_type, _, [{:atom, _, ^module}, {:atom, _, ^name}, _]} -> true
      _ -> false
    end)
  end

  defp has_builtin_type?(term, name) do
    has_type?(term, name) || has_remote_type?(term, :elixir, name)
  end

  defp contains?(term, predicate) do
    predicate.(term) ||
      cond do
        is_tuple(term) ->
          term
          |> Tuple.to_list()
          |> Enum.any?(&contains?(&1, predicate))

        is_list(term) ->
          Enum.any?(term, &contains?(&1, predicate))

        true ->
          false
      end
  end

  # Simple function to remove line numbers from a keyword
  # list of types. Collaterally removes literal integer
  # types, though this is not an issue for our intents.
  defp strip_numbers({line, column}) when is_integer(line) and is_integer(column),
    do: nil

  defp strip_numbers(list) when is_list(list),
    do: Enum.map(list, &strip_numbers/1)

  defp strip_numbers(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&strip_numbers/1) |> List.to_tuple()

  defp strip_numbers(line) when is_integer(line),
    do: nil

  defp strip_numbers(value),
    do: value

  test "defstruct/1 types" do
    module = unique_module("DefstructTypes")

    type_struct_types =
      compile_source("""
      defmodule #{inspect(module)} do
        use TypeStruct

        defstruct name: String.t()
      end
      """)
      |> fetch_types!(module)
      |> Enum.sort()

    literal_types =
      compile_source("""
      defmodule #{inspect(module)} do
        defstruct [:name]

        @type t :: %__MODULE__{name: String.t()}
      end
      """)
      |> fetch_types!(module)
      |> Enum.sort()

    atom_type_struct_types =
      compile_source("""
      defmodule #{inspect(module)} do
        use TypeStruct

        defstruct name: atom
      end
      """)
      |> fetch_types!(module)
      |> Enum.sort()

    assert type_struct_types == literal_types
    assert atom_type_struct_types != literal_types
  end

  test "required keys and defaults" do
    module = unique_module("RequiredKeys")

    compile_source("""
    defmodule #{inspect(module)} do
      use TypeStruct

      defstruct User,
                id: integer,
                name: String.t() \\\\ "",
                email: String.t() | nil \\\\ nil
    end
    """)

    user_module = Module.concat(module, User)

    assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
      struct!(user_module, %{})
    end

    assert struct!(user_module, id: 1) == struct(user_module, id: 1, name: "", email: nil)
  end

  test "nested structs define nested modules and nested types" do
    module = unique_module("Nested")

    modules =
      compile_source("""
      defmodule #{inspect(module)} do
        use TypeStruct

        defstruct User, id: integer
        defstruct Group, users: [User.t()] \\\\ []
      end
      """)

    user_module = Module.concat(module, User)
    group_module = Module.concat(module, Group)
    group_types = fetch_types!(modules, group_module)

    assert struct!(group_module) == struct(group_module, users: [])
    assert has_remote_type?(group_types, user_module, :t)
  end

  test "nested structs resolve parent local types" do
    module = unique_module("LocalTypes")

    modules =
      compile_source("""
      defmodule #{inspect(module)} do
        use TypeStruct

        @type color :: :black | :blue | :brown | :green
        defstruct User, eye_color: color
      end
      """)

    user_module = Module.concat(module, User)
    user_types = fetch_types!(modules, user_module)

    assert has_remote_type?(user_types, module, :color)
  end

  test "nested structs preserve Elixir and Erlang built-in types" do
    module = unique_module("Builtins")

    modules =
      compile_source("""
      defmodule #{inspect(module)} do
        use TypeStruct

        defstruct Item,
                  callback: function,
                  fun: fun,
                  binary: nonempty_binary,
                  bitstring: nonempty_bitstring,
                  chars: nonempty_charlist,
                  keyword: keyword(String.t()),
                  list: nonempty_improper_list(integer, atom)
      end
      """)

    item_module = Module.concat(module, Item)
    item_types = fetch_types!(modules, item_module)

    for type <- [
          :function,
          :fun,
          :nonempty_binary,
          :nonempty_bitstring,
          :nonempty_charlist,
          :keyword,
          :nonempty_improper_list
        ] do
      assert has_builtin_type?(item_types, type)
      refute has_remote_type?(item_types, module, type)
    end
  end

  test "custom type attributes" do
    module = unique_module("CustomTypes")

    modules =
      compile_source("""
      defmodule #{inspect(module)} do
        use TypeStruct

        defstruct Public, type(fields), id: integer
        defstruct Hidden, opaque(fields), id: integer
      end
      """)

    assert [type: {:fields, _, []}] =
             fetch_types!(modules, Module.concat(module, Public))

    assert [opaque: {:fields, _, []}] =
             fetch_types!(modules, Module.concat(module, Hidden))
  end
end
