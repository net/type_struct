defmodule TypeStruct do
  @moduledoc ~S"""
  Defines structs and their types together.

  TypeStruct extends `defstruct` so fields can be declared as `name: type`,
  with optional defaults written as `type \\ default`:

      defmodule Point do
        use TypeStruct

        defstruct x: integer,
                  y: integer
      end

  It can also define nested struct modules:

      defmodule Accounts do
        use TypeStruct

        defstruct User,
                  id: integer,
                  name: String.t() \\ "",
                  eye_color: :black | :blue | :brown | :green

        defstruct Group,
                  id: integer,
                  name: String.t(),
                  users: [User.t()] \\ []
      end

  Fields without defaults are required through `@enforce_keys`. TypeStruct
  defines a public `t/0` type by default, and accepts `type/1`, `typep/1`, or
  `opaque/1` to customize the generated type.
  """

  # Built-in types recognized by Elixir's typespec translator but not reported
  # by `:erl_internal.is_type/2`.
  # Last updated for Elixir 1.19.5.
  # See https://hexdocs.pm/elixir/typespecs.html.
  @elixir_builtin_types [
    as_boolean: 1,
    char_list: 0,
    charlist: 0,
    fun: 0,
    keyword: 0,
    keyword: 1,
    nonempty_charlist: 0,
    struct: 0,
    var: 0
  ]

  defmacro __using__(_opts) do
    quote do
      import TypeStruct
      import Kernel, except: [defstruct: 1]
    end
  end

  @doc ~S"""
  Defines a struct and a matching `t/0` type in the current module.

      defmodule Point do
        use TypeStruct

        defstruct x: integer, y: integer
      end

  Fields without defaults are added to `@enforce_keys`.
  """
  defmacro defstruct(fields)

  defmacro defstruct(keywords),
    do: do_defstruct(keywords, default_type_definition())

  @doc ~S"""
  Defines either a nested struct module or a struct with a custom type.

      defmodule Geometry do
        use TypeStruct

        defstruct Point, x: integer, y: integer
      end

  The example above defines `Geometry.Point` and `Geometry.Point.t/0`.

  If the first argument is a type declaration, the struct is defined in the
  current module with that type:

      defstruct opaque(t), id: integer
      defstruct typep(fields), id: integer
  """
  defmacro defstruct(alias_or_type_definition, fields)

  defmacro defstruct({:__aliases__, _meta, _args} = alias, keywords) do
    do_defmodule_defstruct(alias, __CALLER__, keywords, default_type_definition())
  end

  defmacro defstruct(quoted_type, keywords) do
    do_defstruct(keywords, parse_quoted_type(quoted_type))
  end

  @doc ~S"""
  Defines a nested struct module with a custom type declaration.

      defmodule Accounts do
        use TypeStruct

        defstruct User, opaque(t), id: integer
      end

  The example above defines `Accounts.User` and `@opaque t()`.
  """
  defmacro defstruct(alias, type_definition, fields)

  defmacro defstruct(alias, quoted_type, keywords) do
    do_defmodule_defstruct(alias, __CALLER__, keywords, parse_quoted_type(quoted_type))
  end

  # Convenience function to keep the macro definitions tidy.
  defp do_defmodule_defstruct(alias, caller, keywords, type_definition) do
    alias_types? = caller.module != nil

    quoted_defstruct =
      do_defstruct(keywords, type_definition, alias_types?, caller.module)

    quoted_alias_block = create_quoted_alias_block(caller.aliases)

    quote do
      typedoc =
        with module when module != nil <- __MODULE__,
             {_line, typedoc} <- Module.delete_attribute(module, :typedoc) do
          typedoc
        else
          nil -> nil
        end

      defmodule unquote(alias) do
        unquote(quoted_alias_block)

        @typedoc typedoc
        unquote(quoted_defstruct)
      end
    end
  end

  defp do_defstruct(keywords, type_definition),
    do: do_defstruct(keywords, type_definition, false, nil)

  defp do_defstruct(keywords, type_definition, alias_types?, caller_alias) do
    model =
      keywords
      |> parse_keyword_list
      |> maybe_map_module_to_types(alias_types?, caller_alias)

    defstruct_args =
      for {key, {_, _, default}} <- model, do: {key, default}

    enforce_keys_args =
      for {key, {_, true, _}} <- model, do: key

    quoted_type = create_quoted_type(type_definition, model)

    quote do
      # Must be above struct definition.
      @enforce_keys unquote(enforce_keys_args)

      Kernel.defstruct(unquote(defstruct_args))

      # Now we set the @type/@typep/@opaque attribute.
      unquote(quoted_type)
    end
  end

  defp maybe_map_module_to_types(model, false, _module), do: model

  defp maybe_map_module_to_types(model, true, module) do
    for {key, {type, required, default}} <- model do
      type = maybe_prepend_module(type, module)
      {key, {type, required, default}}
    end
  end

  # Takes a quoted keyword list and returns a model in
  # the format `[key: {type, required?, default}, ...]`
  # where `type` is a quoted representation of the
  # field's type, `required?` is a boolean, and `default`
  # is a quoted representation of the field's default
  # value.
  defp parse_keyword_list(keywords) do
    Enum.map(keywords, fn {key, value} ->
      {key, parse_keyword_value(value)}
    end)
  end

  defp parse_keyword_value({:\\, _meta, [type, default]}),
    do: {type, false, default}

  defp parse_keyword_value(type),
    do: {type, true, nil}

  # Type definitions are described using the format
  # `{type_attribute, type_name}` where `type_attribute`
  # is an atom, and `type_name` is a quoted
  # representation of the type's name.
  defp parse_quoted_type({:type, _meta, [name]}), do: {:type, name}
  defp parse_quoted_type({:typep, _meta, [name]}), do: {:typep, name}
  defp parse_quoted_type({:opaque, _meta, [name]}), do: {:opaque, name}

  defp default_type_definition, do: {:type, {:t, [], Elixir}}

  defp create_quoted_type({type_attribute, quoted_type_name}, model) do
    type_alias_args =
      Enum.map(model, fn {key, {type, _, _}} -> {key, type} end)

    quoted_struct_type =
      {:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], type_alias_args}]}

    create_quoted_type(type_attribute, quoted_type_name, quoted_struct_type)
  end

  defp create_quoted_type(:type, quoted_name, quoted_struct_type),
    do: quote(do: @type(unquote(quoted_name) :: unquote(quoted_struct_type)))

  defp create_quoted_type(:typep, quoted_name, quoted_struct_type),
    do: quote(do: @typep(unquote(quoted_name) :: unquote(quoted_struct_type)))

  defp create_quoted_type(:opaque, quoted_name, quoted_struct_type),
    do: quote(do: @opaque(unquote(quoted_name) :: unquote(quoted_struct_type)))

  # Takes a `Macro.Env.aliases` list, aka
  # `[{alias, module]}`, and returns a quoted block
  # of `alias/2` calls.
  defp create_quoted_alias_block(aliases) do
    for {aliased, actual} <- aliases do
      quote do
        alias unquote(actual), as: unquote(aliased)
      end
    end
  end

  # Takes a quoted type and a module. Walks the quoted
  # type and prepends the module to any type that isn't
  # a built-in.
  defp maybe_prepend_module(list, module) when is_list(list) do
    Enum.map(list, &maybe_prepend_module(&1, module))
  end

  defp maybe_prepend_module({atom, meta, args}, module) when is_atom(atom) do
    with true <- possible_type_name?(atom),
         arity <- quoted_args_arity(args),
         false <- is_builtin?(atom, arity) do
      args = if args, do: maybe_prepend_module(args, module), else: []
      module_atom_parts = split_module_into_atoms(module)
      {{:., [], [{:__aliases__, [], module_atom_parts}, atom]}, [], args}
    else
      _ -> {atom, meta, maybe_prepend_module(args, module)}
    end
  end

  defp maybe_prepend_module({node, meta, args}, module) when is_tuple(node) do
    {maybe_prepend_module(node, module), meta, maybe_prepend_module(args, module)}
  end

  defp maybe_prepend_module(tuple, module) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> maybe_prepend_module(module)
    |> List.to_tuple()
  end

  defp maybe_prepend_module(value, _module) do
    value
  end

  defp possible_type_name?(atom) do
    atom |> Atom.to_string() |> String.match?(~r/^[a-z][a-zA-Z0-9_]*[?!]{0,1}$/)
  end

  defp quoted_args_arity(nil), do: 0
  defp quoted_args_arity(list), do: length(list)

  defp is_builtin?(atom, arity) do
    :erl_internal.is_type(atom, arity) ||
      Enum.member?(Keyword.get_values(@elixir_builtin_types, atom), arity)
  end

  # Converts `Foo.Bar` to `[:Foo, :Bar]` (for example).
  defp split_module_into_atoms(module),
    do: module |> Module.split() |> Enum.map(&String.to_atom/1)
end
