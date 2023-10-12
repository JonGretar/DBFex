# DBF

Read DBASE files in Elixir.

At the moment it only supports read.

## Installation

Do not add this to your dependencies yet. It is not ready.

## DBF File Format

 * http://independent-software.com/dbase-dbf-dbt-file-format.html
 * https://www.clicketyclick.dk/databases/xbase/format/dbf.html#DBF_STRUCT
 * https://wiki.dbfmanager.com/dbf-structure 


## Usage

I'm thinking of something like this:

```elixir

db = DBF.open("test/fixtures/DBASEIII.DBF")

db |> Stream.map(&myfun/1) |> Enum.to_list

DBF.insert(DB, %{name: "John", age: 20})
{:record, _} = DBF.read_record(2)
DBF.delete(db, 2)
{:deleted_record, _} = DBF.read_record(2)

DBF.close(db)
```
