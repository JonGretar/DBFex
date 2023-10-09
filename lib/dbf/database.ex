defmodule DBF.Database do
  defstruct [
    :device,
    :version,
    :last_updated,
    :number_of_records,
    :header_bytes,
    :record_bytes,
    :fields
  ]
  @type t :: %DBF.Database{
    device: File.stream,
    version: integer,
    last_updated: {integer, integer, integer},
    number_of_records: integer,
    header_bytes: integer,
    record_bytes: integer,
    fields: [{binary, binary}]
  }


end
