defmodule TypeStructTest do
  use ExUnit.Case
  doctest TypeStruct

  # Macro to return a list of types from a given module
  # block.
  defmacrop defmodule_types(do: block) do
    quote do
      {_, _, bytecode, _} = defmodule TypeTempModule, do: unquote(block)

      :code.delete(TypeTempModule)
      :code.purge(TypeTempModule)

      bytecode |> Kernel.Typespec.beam_types |> strip_numbers |> Enum.sort
    end
  end

  # Simple function to remove line numbers from a keyword
  # list of types. Collaterally removes literal integer
  # types, though this is not an issue for our intents.
  defp strip_numbers(list) when is_list(list),
    do: Enum.map(list, &strip_numbers/1)
  defp strip_numbers(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list |> Enum.map(&strip_numbers/1) |> List.to_tuple
  defp strip_numbers(line) when is_integer(line),
    do: nil
  defp strip_numbers(value),
    do: value

  # Ill-advised macro to aid with testing types. The ease
  # of testing it provides is worth the magic.
  defmacrop assert_equal_types(do: block) do
    quote do
      unquote(block)
      assert var!(type_struct_types) == var!(literal_types)
    end
  end

  # See the `assert_equal_types/1` macro.
  defmacrop assert_unequal_types(do: block) do
    quote do
      unquote(block)
      assert var!(type_struct_types) != var!(literal_types)
    end
  end

  # Sets the variable `type_struct_types` for use with the
  # `assert_equal_types/1` macro.
  defmacrop type_struct_types(do: block) do
    quote do
      var!(type_struct_types) =
        defmodule_types do
          use TypeStruct
          unquote(block)
        end
    end
  end

  # Sets the variable `literal_types` for use with the
  # `assert_equal_types/1` macro.
  defmacrop literal_types(fields, do: block) do
    quote do
      var!(literal_types) =
        defmodule_types do
          defstruct unquote(fields)
          unquote(block)
        end
    end
  end

  test "defstruct/1 types" do
    assert_equal_types do
      type_struct_types do
        defstruct name: String.t
      end

      literal_types [:name] do
        @type t :: %__MODULE__{name: String.t}
      end
    end

    assert_unequal_types do
      type_struct_types do
        defstruct name: atom
      end

      literal_types [:name] do
        @type t :: %__MODULE__{name: String.t}
      end
    end
  end
end
