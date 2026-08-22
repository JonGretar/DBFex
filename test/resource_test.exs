defmodule DBF.ResourceTest do
  use ExUnit.Case, async: true

  alias DBF.Resource

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "dbf-resource-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    table_path = Path.join(directory, "table.dbf")
    memo_path = Path.join(directory, "table.dbt")
    File.write!(table_path, "table bytes")
    File.write!(memo_path, "memo bytes")

    %{table_path: table_path, memo_path: memo_path, directory: directory}
  end

  test "a successful transaction exposes exact reads and cached table metadata", %{
    table_path: path
  } do
    assert {:ok, resource} =
             Resource.transaction(path, fn resource ->
               assert {:ok, "table"} = Resource.read_exact(resource, :table, 0, 5)
               assert {:ok, 11} = Resource.size(resource, :table)
               assert {:ok, ^path} = Resource.path(resource, :table)
               assert Resource.open?(resource)
               {:ok, resource}
             end)

    assert Resource.open?(resource)
    assert :ok = Resource.close(resource)
  end

  test "a missing table preserves the filesystem cause", %{directory: directory} do
    path = Path.join(directory, "missing.dbf")

    assert {:error,
            %{
              __struct__: DBF.Error,
              reason: :file_not_found,
              cause: :enoent,
              context: %{filename: ^path, source: :table}
            }} = Resource.transaction(path, fn resource -> {:ok, resource} end)
  end

  test "an exact read reports EOF and short-read context", %{table_path: path} do
    assert {:ok, resource} =
             Resource.transaction(path, fn resource ->
               assert {:error,
                       %{
                         __struct__: DBF.Error,
                         reason: :file_error,
                         cause: :eof,
                         context: %{
                           filename: ^path,
                           source: :table,
                           offset: 6,
                           expected: 10,
                           actual: 5
                         }
                       }} = Resource.read_exact(resource, :table, 6, 10)

               {:ok, resource}
             end)

    assert :ok = Resource.close(resource)
  end

  test "an error result rolls the transaction back", %{table_path: path} do
    callback_error = struct(DBF.Error, reason: :invalid_header)

    assert {:error, ^callback_error} =
             Resource.transaction(path, fn resource ->
               send(self(), {:rollback_resource, resource})
               {:error, callback_error}
             end)

    assert_receive {:rollback_resource, resource}
    refute Resource.open?(resource)
  end

  test "a callback raise closes the resource and propagates", %{table_path: path} do
    assert_raise RuntimeError, "callback failed", fn ->
      Resource.transaction(path, fn resource ->
        send(self(), {:raised_resource, resource})
        raise "callback failed"
      end)
    end

    assert_receive {:raised_resource, resource}
    refute Resource.open?(resource)
  end

  test "a callback throw closes the resource and propagates", %{table_path: path} do
    assert catch_throw(
             Resource.transaction(path, fn resource ->
               send(self(), {:thrown_resource, resource})
               throw(:callback_failed)
             end)
           ) == :callback_failed

    assert_receive {:thrown_resource, resource}
    refute Resource.open?(resource)
  end

  test "a callback exit closes the resource and propagates", %{table_path: path} do
    assert catch_exit(
             Resource.transaction(path, fn resource ->
               send(self(), {:exited_resource, resource})
               exit(:callback_failed)
             end)
           ) == :callback_failed

    assert_receive {:exited_resource, resource}
    refute Resource.open?(resource)
  end

  test "a memo can be acquired and read through the same resource", %{
    table_path: table_path,
    memo_path: memo_path
  } do
    assert {:ok, resource} =
             Resource.transaction(table_path, fn resource ->
               assert {:ok, ^resource} = Resource.acquire_memo(resource, memo_path)
               assert {:ok, "memo"} = Resource.read_exact(resource, :memo, 0, 4)
               assert {:ok, 10} = Resource.size(resource, :memo)
               assert {:ok, ^memo_path} = Resource.path(resource, :memo)
               {:ok, resource}
             end)

    assert :ok = Resource.close(resource)
  end

  test "a missing memo has a memo-specific error", %{table_path: table_path, directory: directory} do
    memo_path = Path.join(directory, "missing.dbt")

    assert {:error,
            %{
              __struct__: DBF.Error,
              reason: :missing_memo_file,
              cause: :enoent,
              context: %{filename: ^memo_path, source: :memo}
            }} =
             Resource.transaction(table_path, fn resource ->
               Resource.acquire_memo(resource, memo_path)
             end)
  end

  test "close is idempotent across immutable copies", %{table_path: path} do
    assert {:ok, resource} = Resource.transaction(path, &{:ok, &1})
    copy = struct(Resource, Map.from_struct(resource))

    results =
      [resource, copy]
      |> Enum.map(&Task.async(fn -> Resource.close(&1) end))
      |> Task.await_many()

    assert results == [:ok, :ok]
    assert :ok = Resource.close(resource)
    refute Resource.open?(resource)
  end

  test "the resource closes when its semantic owner dies", %{table_path: path} do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, resource} = Resource.transaction(path, &{:ok, &1})
        send(parent, {:owned_resource, resource})
        Process.sleep(:infinity)
      end)

    assert_receive {:owned_resource, resource}
    assert Resource.open?(resource)

    Process.exit(owner, :kill)
    assert_eventually_closed(resource)
  end

  defp assert_eventually_closed(resource, attempts \\ 50)

  defp assert_eventually_closed(resource, 0) do
    refute Resource.open?(resource)
  end

  defp assert_eventually_closed(resource, attempts) do
    if Resource.open?(resource) do
      Process.sleep(10)
      assert_eventually_closed(resource, attempts - 1)
    else
      :ok
    end
  end
end
