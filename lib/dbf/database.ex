defmodule DBF.Database do
  defstruct [
    :device,
    :version,
    :last_updated,
    :number_of_records,
    :header_bytes,
    :fields
  ]
  @type t :: %DBF.Database{
    device: File.stream,
    version: integer,
    last_updated: {integer, integer, integer},
    number_of_records: integer,
    header_bytes: integer,
    fields: [{binary, binary}]
  }


end
