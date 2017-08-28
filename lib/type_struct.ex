defmodule TypeStruct do
  @moduledoc ~S"""
  TypeStruct provides a concise syntax for defining structs and their types.
  """

  # Elixir built-in types. Last updated for Elixir 1.4.2.
  # See https://hexdocs.pm/elixir/typespecs.html.
  # `:any` represents any arity (0..infinity).
  @builtin_types [
    any: 0,
    none: 0,
    atom: 0,
    map: 0,
    pid: 0,
    port: 0,
    reference: 0,
    struct: 0,
    tuple: 0,
    float: 0,
    integer: 0,
    neg_integer: 0,
    non_neg_integer: 0,
    pos_integer: 0,
    list: 1,
    nonempty_list: 1,
    maybe_improper_list: :any,
    nonempty_improper_list: :any,
    nonempty_maybe_improper_list: :any,
    term: 0,
    arity: 0,
    as_boolean: 1,
    binary: 0,
    bitstring: 0,
    boolean: 0,
    byte: 0,
    char: 0,
    charlist: 0,
    fun: 0,
    identifier: 0,
    iodata: 0,
    iolist: 0,
    keyword: 0,
    keyword: 1,
    list: 0,
    nonempty_list: 0,
    maybe_improper_list: 0,
    nonempty_maybe_improper_list: 0,
    mfa: 0,
    module: 0,
    no_return: 0,
    node: 0,
    number: 0,
    struct: 0,
    timeout: 0
  ]

  defmacro __using__(_opts) do
    quote do
      import TypeStruct
      import Kernel, except: [defstruct: 1]
    end
  end

  # Possible uses:
  # - `defstruct x: integer, y: integer`
  defmacro defstruct(fields)
  defmacro defstruct(keywords),
    do: do_defstruct(keywords, default_type_definition())

  # Possible uses:
  # - `defstruct Point, x: integer, y: integer`
  # - `defstruct type(t), x: integer, y: integer`
  defmacro defstruct(alias_or_type_definition, fields)
  defmacro defstruct({:__aliases__, _meta, _args} = alias, keywords) do
    do_defmodule_defstruct(alias, __CALLER__,
                           keywords, default_type_definition())
  end
  defmacro defstruct(quoted_type, keywords) do
    do_defstruct(keywords, parse_quoted_type(quoted_type))
  end

  # Possible uses:
  # - `defstruct Point, type(t), x: integer, y: integer`
  defmacro defstruct(alias, type_definition, fields)
  defmacro defstruct(alias, quoted_type, keywords) do
    do_defmodule_defstruct(alias, __CALLER__,
                           keywords, parse_quoted_type(quoted_type))
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
      Enum.filter_map(model, &(&1 |> elem(1) |> elem(1)), &elem(&1, 0))

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
    Enum.map keywords, fn({key, value}) ->
      {key, parse_keyword_value(value)}
    end
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
      Enum.map(model, fn({key, {type, _, _}}) -> {key, type} end)

    quoted_struct_type =
      {:%, [], [{:__MODULE__, [], Elixir}, {:%{}, [], type_alias_args}]}

    create_quoted_type(type_attribute, quoted_type_name, quoted_struct_type)
  end

  defp create_quoted_type(:type, quoted_name, quoted_struct_type),
    do: quote do: @type unquote(quoted_name) :: unquote(quoted_struct_type)
  defp create_quoted_type(:typep, quoted_name, quoted_struct_type),
    do: quote do: @typep unquote(quoted_name) :: unquote(quoted_struct_type)
  defp create_quoted_type(:opaque, quoted_name, quoted_struct_type),
    do: quote do: @opaque unquote(quoted_name) :: unquote(quoted_struct_type)

  # Takes a `Macro.Env.aliases` list, aka
  # `[{alias, module]}`, and returns a quoted block
  # of `alias/2` calls.
  defp create_quoted_alias_block(aliases) do
    for {aliased, actual} <- aliases do
      quote do: alias unquote(actual), as: unquote(aliased)
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
      {{:".", [], [{:__aliases__, [], module_atom_parts}, atom]}, [], args}
    else
      _ -> {atom, meta, maybe_prepend_module(args, module)}
    end
  end
  defp maybe_prepend_module({node, meta, args}, module) when is_tuple(node) do
    {maybe_prepend_module(node, module), meta, args}
  end
  defp maybe_prepend_module(value, _module) do
    value
  end

  defp possible_type_name?(atom) do
    atom |> Atom.to_string |> String.match?(~r/^[a-z][a-zA-Z0-9_]*[?!]{0,1}$/)
  end

  defp quoted_args_arity(nil), do: 0
  defp quoted_args_arity(list), do: length(list)

  defp is_builtin?(atom, arity) do
    Enum.any? @builtin_types, fn
      {type, :any} -> type == atom
      {type, type_arity} -> type == atom && type_arity == arity
    end
  end

  # Converts `Foo.Bar` to `[:Foo, :Bar]` (for example).
  defp split_module_into_atoms(module),
    do: module |> Module.split |> Enum.map(&String.to_atom/1)
end
