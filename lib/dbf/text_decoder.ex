defmodule DBF.TextDecoder do
  @moduledoc false

  alias DBF.Error

  @enforce_keys [:encoding, :errors, :language_driver]
  defstruct [:encoding, :errors, :language_driver]

  @type encoding :: :windows_1251 | :windows_1252 | :raw
  @type error_policy :: :strict | :replace | :raw
  @type trim :: :none | :leading | :trailing | :both | :whitespace
  @type t :: %__MODULE__{
          encoding: encoding(),
          errors: error_policy(),
          language_driver: byte() | nil
        }

  @cp1252 %{
    0x80 => 0x20AC,
    0x82 => 0x201A,
    0x83 => 0x0192,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x02C6,
    0x89 => 0x2030,
    0x8A => 0x0160,
    0x8B => 0x2039,
    0x8C => 0x0152,
    0x8E => 0x017D,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x98 => 0x02DC,
    0x99 => 0x2122,
    0x9A => 0x0161,
    0x9B => 0x203A,
    0x9C => 0x0153,
    0x9E => 0x017E,
    0x9F => 0x0178
  }

  @cp1251 %{
    0x80 => 0x0402,
    0x81 => 0x0403,
    0x82 => 0x201A,
    0x83 => 0x0453,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x20AC,
    0x89 => 0x2030,
    0x8A => 0x0409,
    0x8B => 0x2039,
    0x8C => 0x040A,
    0x8D => 0x040C,
    0x8E => 0x040B,
    0x8F => 0x040F,
    0x90 => 0x0452,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x99 => 0x2122,
    0x9A => 0x0459,
    0x9B => 0x203A,
    0x9C => 0x045A,
    0x9D => 0x045C,
    0x9E => 0x045B,
    0x9F => 0x045F,
    0xA0 => 0x00A0,
    0xA1 => 0x040E,
    0xA2 => 0x045E,
    0xA3 => 0x0408,
    0xA4 => 0x00A4,
    0xA5 => 0x0490,
    0xA6 => 0x00A6,
    0xA7 => 0x00A7,
    0xA8 => 0x0401,
    0xA9 => 0x00A9,
    0xAA => 0x0404,
    0xAB => 0x00AB,
    0xAC => 0x00AC,
    0xAD => 0x00AD,
    0xAE => 0x00AE,
    0xAF => 0x0407,
    0xB0 => 0x00B0,
    0xB1 => 0x00B1,
    0xB2 => 0x0406,
    0xB3 => 0x0456,
    0xB4 => 0x0491,
    0xB5 => 0x00B5,
    0xB6 => 0x00B6,
    0xB7 => 0x00B7,
    0xB8 => 0x0451,
    0xB9 => 0x2116,
    0xBA => 0x0454,
    0xBB => 0x00BB,
    0xBC => 0x0458,
    0xBD => 0x0405,
    0xBE => 0x0455,
    0xBF => 0x0457
  }

  @spec compile(byte() | nil, keyword()) :: {:ok, t()} | {:error, Error.t()}
  def compile(language_driver, options) do
    encoding = Keyword.get(options, :encoding, :auto)
    errors = Keyword.get(options, :encoding_errors, :raw)

    case resolve_encoding(encoding, language_driver) do
      {:ok, resolved} ->
        {:ok,
         %__MODULE__{
           encoding: resolved,
           errors: errors,
           language_driver: language_driver
         }}

      {:error, _cause} when errors == :raw ->
        {:ok, %__MODULE__{encoding: :raw, errors: :raw, language_driver: language_driver}}

      {:error, cause} ->
        {:error,
         Error.new(:invalid_encoding, cause, %{
           language_driver: language_driver,
           encoding: encoding
         })}
    end
  end

  @spec decode(t(), binary(), trim()) :: {:ok, binary()} | {:error, Error.t()}
  def decode(%__MODULE__{} = decoder, binary, trim \\ :none) when is_binary(binary) do
    binary = trim(binary, trim)

    case decoder.encoding do
      :raw -> {:ok, binary}
      encoding -> decode_bytes(binary, binary, encoding, decoder.errors, 0, [])
    end
  end

  defp resolve_encoding(:auto, language_driver), do: encoding_for_driver(language_driver)
  defp resolve_encoding(:raw, _language_driver), do: {:ok, :raw}

  defp resolve_encoding(encoding, _language_driver)
       when encoding in [:windows_1251, :windows_1252],
       do: {:ok, encoding}

  defp resolve_encoding(encoding, _language_driver),
    do: {:error, {:unsupported_encoding, encoding}}

  defp encoding_for_driver(0xC9), do: {:ok, :windows_1251}
  defp encoding_for_driver(driver) when driver in [0x03, 0x57], do: {:ok, :windows_1252}
  defp encoding_for_driver(driver) when driver in [nil, 0], do: {:error, :missing_language_driver}
  defp encoding_for_driver(driver), do: {:error, {:unknown_language_driver, driver}}

  defp decode_bytes(<<>>, _original, _encoding, _errors, _offset, characters) do
    {:ok, characters |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp decode_bytes(<<byte, rest::binary>>, original, encoding, errors, offset, characters) do
    case codepoint(encoding, byte) do
      :undefined when errors == :replace ->
        decode_bytes(rest, original, encoding, errors, offset + 1, [<<0xFFFD::utf8>> | characters])

      :undefined when errors == :raw ->
        {:ok, original}

      :undefined ->
        {:error,
         Error.new(:invalid_encoding, :invalid_byte, %{
           encoding: encoding,
           invalid_byte: byte,
           byte_offset: offset
         })}

      codepoint ->
        decode_bytes(rest, original, encoding, errors, offset + 1, [
          <<codepoint::utf8>> | characters
        ])
    end
  end

  defp codepoint(_encoding, byte) when byte < 0x80, do: byte
  defp codepoint(:windows_1252, byte) when byte >= 0xA0, do: byte
  defp codepoint(:windows_1252, byte), do: Map.get(@cp1252, byte, :undefined)
  defp codepoint(:windows_1251, byte) when byte >= 0xC0, do: byte + 0x350
  defp codepoint(:windows_1251, byte), do: Map.get(@cp1251, byte, :undefined)

  @spec trim(binary(), trim()) :: binary()
  def trim(binary, :none), do: binary
  def trim(binary, :leading), do: trim_leading(binary)
  def trim(binary, :trailing), do: trim_trailing(binary)
  def trim(binary, :both), do: binary |> trim_leading() |> trim_trailing()

  def trim(binary, :whitespace),
    do: binary |> trim_leading_whitespace() |> trim_trailing_whitespace()

  defp trim_leading(<<0x20, rest::binary>>), do: trim_leading(rest)
  defp trim_leading(binary), do: binary

  defp trim_trailing(<<>>), do: <<>>

  defp trim_trailing(binary) do
    if :binary.last(binary) == 0x20 do
      trim_trailing(binary_part(binary, 0, byte_size(binary) - 1))
    else
      binary
    end
  end

  defp trim_leading_whitespace(<<byte, rest::binary>>) when byte in [9, 10, 11, 12, 13, 32] do
    trim_leading_whitespace(rest)
  end

  defp trim_leading_whitespace(binary), do: binary
  defp trim_trailing_whitespace(<<>>), do: <<>>

  defp trim_trailing_whitespace(binary) do
    if :binary.last(binary) in [9, 10, 11, 12, 13, 32] do
      trim_trailing_whitespace(binary_part(binary, 0, byte_size(binary) - 1))
    else
      binary
    end
  end
end
