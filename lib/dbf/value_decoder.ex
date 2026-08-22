defmodule DBF.ValueDecoder do
  @moduledoc false

  alias DBF.Error
  alias DBF.Field
  alias DBF.FormatProfile
  alias DBF.Memo

  @spec compile(Field.t(), FormatProfile.t(), DBF.options()) :: Field.decoder()
  def compile(%Field{type: "C"}, %FormatProfile{}, _options), do: {:text, :character}
  def compile(%Field{type: "V"}, %FormatProfile{}, _options), do: {:text, :variable_character}
  def compile(%Field{type: "F"}, %FormatProfile{}, _options), do: {:text, :float}
  def compile(%Field{type: "I"}, %FormatProfile{}, _options), do: {:binary, :integer}
  def compile(%Field{type: "Y"}, %FormatProfile{}, _options), do: {:binary, :currency}
  def compile(%Field{type: "L"}, %FormatProfile{}, _options), do: {:text, :logical}

  def compile(%Field{type: "N"}, %FormatProfile{}, options) do
    {:text, {:numeric, Keyword.get(options, :numeric, :float)}}
  end

  def compile(%Field{type: "M"}, %FormatProfile{}, _options), do: {:text, :memo}
  def compile(%Field{type: "0"}, %FormatProfile{}, _options), do: {:binary, :null_flags}
  def compile(%Field{type: "D"}, %FormatProfile{}, _options), do: {:text, :date}
  def compile(%Field{type: type}, %FormatProfile{}, _options), do: {:unsupported, type}

  @spec decode(DBF.Database.t(), Field.t(), binary()) :: term() | {:error, Error.t()}
  def decode(_db, _field, ""), do: nil

  def decode(_db, %{decoder: {:text, :character}}, value), do: String.trim(value)
  def decode(_db, %{decoder: {:text, :variable_character}}, value), do: String.trim(value)

  def decode(_db, %{decoder: {:text, :float}}, value) do
    trimmed = String.trim(value)

    case Float.parse(trimmed) do
      {number, ""} -> number
      :error when trimmed == "" -> nil
      _invalid -> invalid_value("Illegal float value: #{inspect(value)}")
    end
  end

  def decode(_db, %{decoder: {:binary, :integer}}, <<value::signed-big-integer-32>>), do: value

  def decode(
        _db,
        %{decoder: {:binary, :currency}, decimal: decimal},
        <<value::signed-little-integer-64>>
      ) do
    value / :math.pow(10, decimal)
  end

  def decode(_db, %{decoder: {:text, :logical}}, value) do
    case value do
      logical when logical in ["Y", "y", "T", "t"] -> true
      logical when logical in ["N", "n", "F", "f"] -> false
      logical when logical in ["?", " "] -> nil
      other -> invalid_value("Illegal logical value: #{other}")
    end
  end

  def decode(_db, %{decoder: {:text, {:numeric, :float}}}, value) do
    case value |> String.trim() |> Float.parse() do
      {number, ""} -> number
      _invalid -> nil
    end
  end

  def decode(_db, %{decoder: {:text, {:numeric, :exact}}, decimal: 0}, value) do
    case value |> String.trim() |> Integer.parse() do
      {integer, ""} -> integer
      _invalid -> nil
    end
  end

  def decode(
        _db,
        %{decoder: {:text, {:numeric, :exact}}, length: length},
        value
      ) do
    case Decimal.parse(String.trim(value), max_digits: length, max_exponent: length) do
      {%Decimal{} = decimal, ""} -> decimal
      _invalid -> nil
    end
  end

  def decode(db, %{decoder: {:text, :memo}}, value) do
    new_value = String.trim(value)

    case Integer.parse(new_value) do
      {_block, rest} when rest != "" ->
        {:error, Error.new(:invalid_memo, :invalid_memo_pointer, %{raw_pointer: new_value})}

      {block, ""} ->
        Memo.get_block(db.resource, db.memo_file, block)

      :error when new_value == "" ->
        nil

      :error ->
        {:error, Error.new(:invalid_memo, :invalid_memo_pointer, %{raw_pointer: new_value})}
    end
  end

  def decode(_db, %{decoder: {:binary, :null_flags}}, _value), do: nil
  def decode(_db, %{decoder: {:text, :date}}, "        "), do: nil

  def decode(_db, %{decoder: {:text, :date}}, value) do
    case value do
      <<year::binary-size(4), month::binary-size(2), day::binary-size(2)>> ->
        case Date.from_iso8601("#{year}-#{month}-#{day}") do
          {:ok, date} -> date
          {:error, _reason} -> invalid_value("Invalid date value: #{inspect(value)}")
        end

      _invalid ->
        invalid_value("Invalid date value: #{inspect(value)}")
    end
  end

  def decode(_db, %{decoder: {:unsupported, _type}}, _value) do
    {:error, Error.new(:unsupported_field_type, nil, %{})}
  end

  def decode(_db, _field, _value) do
    {:error, Error.new(:unsupported_field_type, nil, %{})}
  end

  defp invalid_value(message) do
    {:error, Error.new(:invalid_record, {:field_decode_failed, message}, %{})}
  end
end
