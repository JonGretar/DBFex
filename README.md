# DBF

Read DBASE files in Elixir.

At the moment it only supports read.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dbf` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dbf, "~> 0.1.0"}
  ]
end
```

 * http://independent-software.com/dbase-dbf-dbt-file-format.html
 * https://www.clicketyclick.dk/databases/xbase/format/dbf.html#DBF_STRUCT
 * https://wiki.dbfmanager.com/dbf-structure 

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/dbf>.

## Usage

```elixir

db = DBF.open("test/fixtures/DBASEIII.DBF")


db |> Stream.map(&myfun/1) |> Enum.to_list

DBF.insert(DB, %{name: "John", age: 20})
{:record, _} = DBF.read_record(2)
DBF.delete(db, 2)
{:deleted_record, _} = DBF.read_record(2)

DBF.close(db)

```
