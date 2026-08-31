defmodule DBF.Header do
  @moduledoc false

  alias DBF.Error
  alias DBF.FormatProfile

  @foxbase_header_size 8
  @legacy_header_size 32

  @enforce_keys [
    :version,
    :date,
    :record_count,
    :header_length,
    :record_length,
    :table_flags,
    :language_driver
  ]
  defstruct [
    :version,
    :date,
    :record_count,
    :header_length,
    :record_length,
    :table_flags,
    :language_driver
  ]

  @type t :: %__MODULE__{
          version: byte(),
          date: Date.t(),
          record_count: non_neg_integer(),
          header_length: pos_integer(),
          record_length: pos_integer(),
          table_flags: byte() | nil,
          language_driver: byte() | nil
        }

  @spec required_bytes(FormatProfile.t()) :: pos_integer()
  def required_bytes(%FormatProfile{header_layout: layout}), do: header_size(layout)

  @spec parse(term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def parse(binary, %FormatProfile{} = profile, file_size) when is_binary(binary) do
    with :ok <- validate_file_size(file_size),
         :ok <- validate_binary_size(binary, profile.header_layout),
         {:ok, values} <- decode(binary, profile.header_layout),
         :ok <- validate_version(values.version, profile),
         {:ok, date} <- parse_date(values.date),
         :ok <- validate_lengths(values, profile.header_layout),
         :ok <- validate_file_bounds(values, file_size) do
      {:ok,
       %__MODULE__{
         version: values.version,
         date: date,
         record_count: values.record_count,
         header_length: values.header_length,
         record_length: values.record_length,
         table_flags: values.table_flags,
         language_driver: values.language_driver
       }}
    end
  end

  def parse(binary, %FormatProfile{} = profile, _file_size) do
    {:error,
     invalid_header(:invalid_header_binary, %{
       actual_bytes: byte_size_if_binary(binary),
       expected_bytes: header_size(profile.header_layout),
       offset: 0
     })}
  end

  def parse(_binary, profile, _file_size) do
    {:error, invalid_header(:invalid_format_profile, %{profile: profile, offset: 0})}
  end

  defp validate_file_size(file_size) when is_integer(file_size) and file_size >= 0, do: :ok

  defp validate_file_size(file_size) do
    {:error, invalid_header(:invalid_file_size, %{file_size: file_size, offset: 0})}
  end

  defp validate_binary_size(binary, layout)
       when layout in [:foxbase_8, :dbase_legacy_32, :visual_foxpro_32] do
    expected = header_size(layout)
    actual = byte_size(binary)

    if actual == expected do
      :ok
    else
      {:error,
       invalid_header(:invalid_header_size, %{
         expected_bytes: expected,
         actual_bytes: actual,
         offset: min(actual, expected)
       })}
    end
  end

  defp validate_binary_size(_binary, layout) do
    {:error, invalid_header(:invalid_format_profile, %{header_layout: layout, offset: 0})}
  end

  # FoxBase layout reference:
  # https://www.clicketyclick.dk/databases/xbase/format/index.html
  defp decode(
         <<version, record_count::little-unsigned-integer-size(16), _unknown::binary-size(3),
           record_length::little-unsigned-integer-size(16)>>,
         :foxbase_8
       ) do
    {:ok,
     %{
       version: version,
       date: {1900, 1, 1},
       record_count: record_count,
       header_length: 521,
       record_length: record_length,
       table_flags: nil,
       language_driver: nil
     }}
  end

  # dBASE III/IV and Visual FoxPro share these core header offsets:
  # https://blogs.embarcadero.com/dbase-dbf-file-structure/
  # https://learn.microsoft.com/en-us/previous-versions/visualstudio/foxpro/st4a0s68(v=vs.71)
  defp decode(
         <<version, year, month, day, record_count::little-unsigned-integer-size(32),
           header_length::little-unsigned-integer-size(16),
           record_length::little-unsigned-integer-size(16), _reserved_1::binary-size(2),
           _transaction, _encryption, _reserved_2::binary-size(12), table_flags, language_driver,
           _reserved_3::binary-size(2)>>,
         layout
       )
       when layout in [:dbase_legacy_32, :visual_foxpro_32] do
    {:ok,
     %{
       version: version,
       date: {year + 1900, month, day},
       record_count: record_count,
       header_length: header_length,
       record_length: record_length,
       table_flags: table_flags,
       language_driver: language_driver
     }}
  end

  defp validate_version(version, %FormatProfile{version: version}), do: :ok

  defp validate_version(version, %FormatProfile{version: profile_version}) do
    {:error,
     invalid_header(:version_mismatch, %{
       version: version,
       profile_version: profile_version,
       offset: 0
     })}
  end

  defp parse_date({year, month, day}) do
    case Date.new(year, month, day) do
      {:ok, date} ->
        {:ok, date}

      {:error, cause} ->
        {:error,
         invalid_header({:invalid_date, cause}, %{
           year: year,
           month: month,
           day: day,
           offset: 1
         })}
    end
  end

  defp validate_lengths(%{header_length: header_length}, :foxbase_8)
       when header_length != 521 do
    {:error,
     invalid_header(:invalid_header_length, %{
       header_length: header_length,
       offset: 0
     })}
  end

  defp validate_lengths(%{header_length: header_length}, layout)
       when layout in [:dbase_legacy_32, :visual_foxpro_32] and
              header_length < 33 do
    {:error,
     invalid_header(:invalid_header_length, %{
       header_length: header_length,
       minimum: 33,
       offset: 8
     })}
  end

  defp validate_lengths(%{record_length: record_length}, layout) when record_length < 1 do
    {:error,
     invalid_header(:invalid_record_length, %{
       record_length: record_length,
       minimum: 1,
       offset: record_length_offset(layout)
     })}
  end

  defp validate_lengths(_values, _layout), do: :ok

  defp validate_file_bounds(values, file_size) do
    required_file_size = values.header_length + values.record_count * values.record_length

    if required_file_size <= file_size do
      :ok
    else
      {:error,
       invalid_header(:records_out_of_bounds, %{
         header_length: values.header_length,
         record_count: values.record_count,
         record_length: values.record_length,
         required_file_size: required_file_size,
         file_size: file_size,
         offset: values.header_length
       })}
    end
  end

  defp invalid_header(cause, context), do: Error.new(:invalid_header, cause, context)

  defp header_size(:foxbase_8), do: @foxbase_header_size
  defp header_size(:dbase_legacy_32), do: @legacy_header_size
  defp header_size(:visual_foxpro_32), do: @legacy_header_size
  defp header_size(_layout), do: 0

  defp record_length_offset(:foxbase_8), do: 6
  defp record_length_offset(:dbase_legacy_32), do: 10
  defp record_length_offset(:visual_foxpro_32), do: 10

  defp byte_size_if_binary(binary) when is_binary(binary), do: byte_size(binary)
  defp byte_size_if_binary(_binary), do: nil
end
