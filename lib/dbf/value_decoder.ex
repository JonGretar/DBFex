defmodule DBF.ValueDecoder do
  @moduledoc false

  alias DBF.Error
  alias DBF.Field
  alias DBF.FormatProfile
  alias DBF.Memo
  alias DBF.TextDecoder

  @spec compile(Field.t(), FormatProfile.t(), DBF.options()) :: Field.decoder()
  def compile(%Field{type: type}, %FormatProfile{field_kinds: field_kinds}, options) do
    case Map.fetch(field_kinds, type) do
      {:ok, kind} -> compile_kind(kind, options)
      :error -> {:unsupported, type}
    end
  end

  defp compile_kind(:character, _options), do: {:text, :character}
  defp compile_kind(:float, _options), do: {:text, :float}
  defp compile_kind(:logical, _options), do: {:text, :logical}
  defp compile_kind(:date, _options), do: {:text, :date}
  defp compile_kind(:text_memo, _options), do: {:text, :memo}

  defp compile_kind(:numeric, options) do
    {:text, {:numeric, Keyword.get(options, :numeric, :float)}}
  end

  @spec decode(DBF.Database.t(), Field.t(), binary()) :: term() | {:error, Error.t()}
  def decode(_db, _field, ""), do: nil

  def decode(db, %{decoder: {:text, :character}}, value) do
    decode_text(db.text_decoder, value, :both)
  end

  def decode(_db, %{decoder: {:text, :float}}, value) do
    trimmed = TextDecoder.trim(value, :both)

    case Float.parse(trimmed) do
      {number, ""} -> number
      :error when trimmed == "" -> nil
      _invalid -> invalid_value("Illegal float value: #{inspect(value)}")
    end
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
    case value |> TextDecoder.trim(:both) |> Float.parse() do
      {number, ""} -> number
      _invalid -> nil
    end
  end

  def decode(_db, %{decoder: {:text, {:numeric, :exact}}, decimal: 0}, value) do
    case value |> TextDecoder.trim(:both) |> Integer.parse() do
      {integer, ""} -> integer
      _invalid -> nil
    end
  end

  def decode(
        _db,
        %{decoder: {:text, {:numeric, :exact}}, length: length},
        value
      ) do
    case Decimal.parse(TextDecoder.trim(value, :both),
           max_digits: length,
           max_exponent: length
         ) do
      {%Decimal{} = decimal, ""} -> decimal
      _invalid -> nil
    end
  end

  def decode(db, %{decoder: {:text, :memo}}, value) do
    new_value = TextDecoder.trim(value, :both)

    case Integer.parse(new_value) do
      {_block, rest} when rest != "" ->
        {:error, Error.new(:invalid_memo, :invalid_memo_pointer, %{raw_pointer: new_value})}

      {block, ""} ->
        case Memo.get_block(db.resource, db.memo_file, block) do
          {:error, %Error{}} = error -> error
          memo -> decode_text(db.text_decoder, memo, :none)
        end

      :error when new_value == "" ->
        nil

      :error ->
        {:error, Error.new(:invalid_memo, :invalid_memo_pointer, %{raw_pointer: new_value})}
    end
  end

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

  defp decode_text(text_decoder, value, trim) do
    case TextDecoder.decode(text_decoder, value, trim) do
      {:ok, decoded} -> decoded
      {:error, %Error{}} = error -> error
    end
  end

  defp invalid_value(message) do
    {:error, Error.new(:invalid_record, {:field_decode_failed, message}, %{})}
  end
end
