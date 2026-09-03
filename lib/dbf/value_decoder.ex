defmodule DBF.ValueDecoder do
  @moduledoc false

  import Bitwise, only: [band: 2]

  alias DBF.Error
  alias DBF.Field
  alias DBF.FormatProfile
  alias DBF.Memo
  alias DBF.TextDecoder

  @spec compile(Field.t(), FormatProfile.t(), DBF.options()) :: Field.decoder()
  def compile(%Field{type: type} = field, %FormatProfile{field_kinds: field_kinds}, options) do
    case Map.fetch(field_kinds, type) do
      {:ok, :variable} -> compile_variable(field)
      {:ok, :character} -> compile_character(field)
      {:ok, :text_memo_binary_pointer} -> compile_memo(field)
      {:ok, kind} -> compile_kind(kind, options)
      :error -> {:unsupported, type}
    end
  end

  defp compile_variable(%Field{flags: flags}) when band(flags, 0x04) == 0x04,
    do: {:binary, :varbinary}

  defp compile_variable(%Field{}), do: {:text, :varchar}

  defp compile_character(%Field{flags: flags})
       when is_integer(flags) and band(flags, 0x04) == 0x04,
       do: {:binary, :binary_character}

  defp compile_character(%Field{}), do: {:text, :character}

  defp compile_memo(%Field{flags: flags}) when band(flags, 0x04) == 0x04,
    do: {:binary, :binary_memo}

  defp compile_memo(%Field{}), do: {:binary, :text_memo}

  defp compile_kind(:float, _options), do: {:text, :float}
  defp compile_kind(:logical, _options), do: {:text, :logical}
  defp compile_kind(:date, _options), do: {:text, :date}
  defp compile_kind(:text_memo, _options), do: {:text, :memo}
  defp compile_kind(:integer, _options), do: {:binary, :integer}
  defp compile_kind(:currency, _options), do: {:binary, :currency}
  defp compile_kind(:double, _options), do: {:binary, :double}
  defp compile_kind(:datetime, _options), do: {:binary, :datetime}
  defp compile_kind(:binary_memo_pointer, _options), do: {:binary, :binary_memo}
  defp compile_kind(:picture_memo_pointer, _options), do: {:binary, :picture_memo}
  defp compile_kind(:general_memo_pointer, _options), do: {:binary, :general_memo}

  defp compile_kind(:numeric, options) do
    {:text, {:numeric, Keyword.get(options, :numeric, :float)}}
  end

  defp compile_kind(:numeric_unscaled, options) do
    case Keyword.get(options, :numeric, :float) do
      :float -> {:text, {:numeric, :float}}
      :exact -> {:text, {:numeric, :exact_unscaled}}
    end
  end

  @spec decode(DBF.Database.t(), Field.t(), binary()) :: term() | {:error, Error.t()}
  def decode(db, %{decoder: {:text, :character}}, value) do
    decode_text(db.text_decoder, value, :both)
  end

  def decode(db, %{decoder: {:text, :varchar}}, value) do
    decode_text(db.text_decoder, value, :none)
  end

  def decode(_db, %{decoder: {:binary, :varbinary}}, value), do: value
  def decode(_db, %{decoder: {:binary, :binary_character}}, value), do: value

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

  def decode(_db, %{decoder: {:text, {:numeric, :exact_unscaled}}, length: length}, value) do
    trimmed = TextDecoder.trim(value, :both)

    case Integer.parse(trimmed) do
      {integer, ""} ->
        integer

      _not_an_integer ->
        case Decimal.parse(trimmed, max_digits: length, max_exponent: length) do
          {%Decimal{} = decimal, ""} -> decimal
          _invalid -> nil
        end
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
        read_text_memo(db, block)

      :error when new_value == "" ->
        nil

      :error ->
        {:error, Error.new(:invalid_memo, :invalid_memo_pointer, %{raw_pointer: new_value})}
    end
  end

  def decode(
        db,
        %{decoder: {:binary, :text_memo}},
        <<block::little-unsigned-integer-size(32)>>
      ) do
    if block == 0, do: nil, else: read_text_memo(db, block)
  end

  def decode(
        db,
        %{decoder: {:binary, :binary_memo}},
        <<block::little-unsigned-integer-size(32)>>
      ) do
    if block == 0, do: nil, else: read_binary_memo(db, block)
  end

  def decode(
        db,
        %{decoder: {:binary, :picture_memo}},
        <<block::little-unsigned-integer-size(32)>>
      ) do
    if block == 0, do: nil, else: read_picture_memo(db, block)
  end

  def decode(
        db,
        %{decoder: {:binary, :general_memo}},
        <<block::little-unsigned-integer-size(32)>>
      ) do
    if block == 0, do: nil, else: read_general_memo(db, block)
  end

  def decode(
        _db,
        %{decoder: {:binary, :integer}},
        <<integer::little-signed-integer-size(32)>>
      ) do
    integer
  end

  def decode(
        _db,
        %{decoder: {:binary, :currency}},
        <<integer::little-signed-integer-size(64)>>
      ) do
    Decimal.new("#{integer}E-4")
  end

  def decode(_db, %{decoder: {:binary, :double}}, <<double::little-float-size(64)>>),
    do: double

  def decode(_db, %{decoder: {:binary, :datetime}}, <<0::size(64)>>), do: nil

  def decode(
        _db,
        %{decoder: {:binary, :datetime}},
        <<julian_day::little-unsigned-integer-size(32),
          milliseconds::little-unsigned-integer-size(32)>> = value
      ) do
    gregorian_days = julian_day - 1_721_060

    if gregorian_days >= 0 and milliseconds < 86_400_000 do
      date = Date.from_gregorian_days(gregorian_days)
      seconds = div(milliseconds, 1000)
      precision = {rem(milliseconds, 1000) * 1000, 3}
      time = Time.from_seconds_after_midnight(seconds, precision)
      {:ok, datetime} = NaiveDateTime.new(date, time)
      datetime
    else
      invalid_value("Invalid datetime value: #{inspect(value)}")
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

  defp read_text_memo(db, block) do
    case Memo.get_block(db.resource, db.memo_file, block, :text) do
      {:error, %Error{}} = error -> error
      memo -> decode_text(db.text_decoder, memo, :none)
    end
  end

  defp read_binary_memo(db, block) do
    Memo.get_block(db.resource, db.memo_file, block, :binary)
  end

  defp read_picture_memo(db, block) do
    Memo.get_block(db.resource, db.memo_file, block, :picture)
  end

  defp read_general_memo(db, block) do
    Memo.get_block(db.resource, db.memo_file, block, :general)
  end

  defp invalid_value(message) do
    {:error, Error.new(:invalid_record, {:field_decode_failed, message}, %{})}
  end
end
