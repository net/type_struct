# TypeStruct

TypeStruct defines structs and their types together.

## Installation

Add `:type_struct` to your dependencies:

```elixir
def deps do
  [
    {:type_struct, "~> 1.0"}
  ]
end
```

## Usage

```elixir
defmodule Point do
  use TypeStruct

  defstruct x: integer,
            y: integer
end
```

TypeStruct can also define nested struct modules:

```elixir
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
```

Each field is written as `name: type`. A default can be given with `\\`:

```elixir
defstruct User, name: String.t() \\ ""
```

Fields without defaults are required via `@enforce_keys`:

```elixir
defstruct User, id: integer, name: String.t() \\ ""
```

If you want a field to default to `nil`, declare that default explicitly:

```elixir
defstruct User, email: String.t() | nil \\ nil
```

## Types

By default, TypeStruct defines a public `t/0` type for every struct:

```elixir
defmodule Accounts do
  use TypeStruct

  defstruct User, id: integer
end
```

The `Accounts.User` example above is equivalent to:

```elixir
defmodule Accounts.User do
  defstruct [:id]

  @type t() :: %__MODULE__{id: integer}
end
```

You can choose a different type attribute or name:

```elixir
defstruct User, type(fields), id: integer
# @type fields() :: %__MODULE__{id: integer}

defstruct User, typep(fields), id: integer
# @typep fields() :: %__MODULE__{id: integer}

defstruct User, opaque(t), id: integer
# @opaque t() :: %__MODULE__{id: integer}
```

The field types are regular Elixir typespecs. Local types referenced by nested
structs are resolved against the parent module, while built-in types are left
untouched:

```elixir
defmodule Catalog do
  use TypeStruct

  @type color :: :red | :green | :blue

  defstruct Product,
            color: color,
            tags: nonempty_list(String.t())
end
```

Here `color` means `Catalog.color/0`, while `nonempty_list/1` is the built-in
type.

## Typedocs

A `@typedoc` placed immediately before a nested `defstruct` is moved into the
generated module:

```elixir
defmodule Accounts do
  use TypeStruct

  @typedoc "A user in the current account."
  defstruct User, id: integer
end
```
