# DBF

Read DBASE files in Elixir.

At the moment it only supports read.

## Installation

The package is a work in progress. It is not yet available in hex.

I will release it in a couple of weeks.


## Usage

Open a file with open/1 or open/2 

```elixir

{:ok, db} = DBF.open("test/dbf_files/bayarea_zipcodes.dbf")
```

The resulting DB follows the enumerable protocol, so you can use all the functions in the Enum module.

So to get all the records of a database you can do:

```elixir
db |> Enum.to_list()
```

The result will be a tuple ´{status, %{...}}´ with the record status being either :record or :deleted_record.

You can get specific rows by using the `DBF.read_record/2` function.

```elixir
case DBF.read_record(db, 2) do
  {:record, row} -> IO.inspect row
  {:deleted_record, row} -> IO.inspect row
  :eof -> IO.puts "End of file"
end
```

## DBF File Format

 * http://independent-software.com/dbase-dbf-dbt-file-format.html
 * https://www.clicketyclick.dk/databases/xbase/format/dbf.html#DBF_STRUCT
 * https://wiki.dbfmanager.com/dbf-structure 

