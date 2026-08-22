defmodule DBF.ErrorTest do
  use ExUnit.Case, async: true

  alias DBF.Error

  test "new/3 stores the reason, cause, and context" do
    assert %Error{
             reason: :invalid_header,
             cause: :invalid_date,
             context: %{offset: 1}
           } = Error.new(:invalid_header, :invalid_date, %{offset: 1})
  end

  test "add_context keeps existing, more specific context" do
    error = Error.new(:invalid_header, :invalid_date, %{offset: 1, version: 0x03})

    assert %Error{context: %{offset: 1, version: 0x03, filename: "sample.dbf"}} =
             Error.add_context(error, %{offset: 0, filename: "sample.dbf"})
  end

  test "DatabaseError preserves the internal cause and context" do
    internal =
      Error.new(:invalid_schema, :missing_descriptor_terminator, %{
        filename: "sample.dbf",
        version: 0x03,
        offset: 64
      })

    assert %DBF.DatabaseError{
             reason: :invalid_schema,
             cause: :missing_descriptor_terminator,
             context: %{filename: "sample.dbf", version: 0x03, offset: 64}
           } = error = DBF.DatabaseError.from_internal(internal)

    assert Exception.message(error) =~ "sample.dbf"
    assert Exception.message(error) =~ "0x03"
    assert Exception.message(error) =~ "64"
  end
end
