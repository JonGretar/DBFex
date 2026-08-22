defmodule DBF.Resource do
  @moduledoc false

  use GenServer

  alias DBF.Error

  @enforce_keys [:pid, :token]
  defstruct [:pid, :token]

  @opaque t() :: %__MODULE__{pid: pid(), token: reference()}
  @type role() :: :table | :memo
  @type result(value) :: {:ok, value} | {:error, Error.t()}

  @spec transaction(Path.t(), (t() -> result(value))) :: result(value) when value: var
  def transaction(table_path, fun) when is_binary(table_path) and is_function(fun, 1) do
    owner = self()
    token = make_ref()

    case GenServer.start(__MODULE__, {owner, token, table_path}) do
      {:ok, pid} -> run_transaction(%__MODULE__{pid: pid, token: token}, fun)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @spec acquire_memo(t(), Path.t()) :: result(t())
  def acquire_memo(%__MODULE__{} = resource, memo_path) when is_binary(memo_path) do
    case call(resource, {:acquire_memo, memo_path}) do
      :ok -> {:ok, resource}
      {:error, _error} = error -> error
    end
  end

  @spec read_exact(t(), role(), non_neg_integer(), non_neg_integer()) :: result(binary())
  def read_exact(%__MODULE__{} = resource, role, offset, length)
      when role in [:table, :memo] and is_integer(offset) and offset >= 0 and is_integer(length) and
             length >= 0 do
    call(resource, {:read_exact, role, offset, length})
  end

  @spec size(t(), role()) :: result(non_neg_integer())
  def size(%__MODULE__{} = resource, role) when role in [:table, :memo] do
    call(resource, {:size, role})
  end

  @spec path(t(), role()) :: result(Path.t())
  def path(%__MODULE__{} = resource, role) when role in [:table, :memo] do
    call(resource, {:path, role})
  end

  @spec close(t()) :: :ok | {:error, Error.t()}
  def close(%__MODULE__{} = resource) do
    GenServer.call(resource.pid, {resource.token, :close})
  catch
    :exit, reason ->
      if closed_exit?(reason) do
        :ok
      else
        {:error, error(:close_failed, reason, %{source: :resource})}
      end
  end

  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{} = resource) do
    GenServer.call(resource.pid, {resource.token, :open?})
  catch
    :exit, _reason -> false
  end

  @impl GenServer
  def init({owner, token, table_path}) do
    owner_monitor = Process.monitor(owner)

    case open_file(table_path, :table) do
      {:ok, file} ->
        {:ok,
         %{
           owner: owner,
           owner_monitor: owner_monitor,
           token: token,
           table: file,
           memo: nil
         }}

      {:error, error} ->
        Process.demonitor(owner_monitor, [:flush])
        {:stop, error}
    end
  end

  @impl GenServer
  def handle_call({token, :open?}, _from, %{token: token} = state) do
    {:reply, true, state}
  end

  def handle_call({token, {:acquire_memo, memo_path}}, _from, %{token: token, memo: nil} = state) do
    case open_file(memo_path, :memo) do
      {:ok, memo} -> {:reply, :ok, %{state | memo: memo}}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({token, {:acquire_memo, memo_path}}, _from, %{token: token} = state) do
    if state.memo.path == memo_path do
      {:reply, :ok, state}
    else
      error = error(:file_error, :memo_already_acquired, %{filename: memo_path, source: :memo})
      {:reply, {:error, error}, state}
    end
  end

  def handle_call({token, {:read_exact, role, offset, length}}, _from, %{token: token} = state) do
    reply =
      case Map.fetch!(state, role) do
        nil -> {:error, unavailable_role_error(role, state)}
        file -> pread_exact(file, role, offset, length)
      end

    {:reply, reply, state}
  end

  def handle_call({token, {:size, role}}, _from, %{token: token} = state) do
    reply =
      case Map.fetch!(state, role) do
        nil -> {:error, unavailable_role_error(role, state)}
        file -> {:ok, file.size}
      end

    {:reply, reply, state}
  end

  def handle_call({token, {:path, role}}, _from, %{token: token} = state) do
    reply =
      case Map.fetch!(state, role) do
        nil -> {:error, unavailable_role_error(role, state)}
        file -> {:ok, file.path}
      end

    {:reply, reply, state}
  end

  def handle_call({token, :close}, _from, %{token: token} = state) do
    result = close_files(state)
    {:stop, :normal, result, state}
  end

  def handle_call({_invalid_token, :open?}, _from, state) do
    {:reply, false, state}
  end

  def handle_call({_invalid_token, _request}, _from, state) do
    {:reply, {:error, error(:file_error, :invalid_resource, %{})}, state}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, monitor, :process, owner, _reason},
        %{
          owner_monitor: monitor,
          owner: owner
        } = state
      ) do
    _ = close_files(state)
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run_transaction(resource, fun) do
    case fun.(resource) do
      {:ok, _value} = result ->
        result

      {:error, error} = result when is_struct(error, Error) ->
        _ = close(resource)
        result

      other ->
        _ = close(resource)

        raise ArgumentError,
              "DBF resource transaction callback must return {:ok, value} or {:error, %DBF.Error{}}, got: #{inspect(other)}"
    end
  catch
    kind, reason ->
      stacktrace = __STACKTRACE__
      _ = close(resource)
      :erlang.raise(kind, reason, stacktrace)
  end

  defp call(resource, request) do
    GenServer.call(resource.pid, {resource.token, request})
  catch
    :exit, reason ->
      {:error, error(:file_error, reason, %{source: request_source(request)})}
  end

  defp open_file(path, role) do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, device} -> cache_opened_file(device, path, role)
      {:error, cause} -> {:error, open_error(path, role, cause)}
    end
  end

  defp cache_opened_file(device, path, role) do
    case :file.position(device, :eof) do
      {:ok, size} ->
        {:ok, %{device: device, path: path, size: size}}

      {:error, cause} ->
        _ = File.close(device)
        {:error, error(:file_error, cause, %{filename: path, source: role})}
    end
  end

  defp open_error(path, :table, :enoent) do
    error(:file_not_found, :enoent, %{filename: path, source: :table})
  end

  defp open_error(path, :memo, :enoent) do
    error(:missing_memo_file, :enoent, %{filename: path, source: :memo})
  end

  defp open_error(path, role, cause) do
    error(:file_error, cause, %{filename: path, source: role})
  end

  defp pread_exact(file, role, offset, length) do
    context = %{
      filename: file.path,
      source: role,
      offset: offset,
      expected: length
    }

    case :file.pread(file.device, offset, length) do
      {:ok, data} when byte_size(data) == length ->
        {:ok, data}

      {:ok, data} ->
        {:error, error(:file_error, :eof, Map.put(context, :actual, byte_size(data)))}

      :eof ->
        {:error, error(:file_error, :eof, Map.put(context, :actual, 0))}

      {:error, cause} ->
        {:error, error(:file_error, cause, Map.put(context, :actual, 0))}
    end
  end

  defp unavailable_role_error(:memo, state) do
    error(:missing_memo_file, :not_acquired, %{
      filename: nil,
      source: :memo,
      table: state.table.path
    })
  end

  defp close_files(state) do
    failures =
      [memo: state.memo, table: state.table]
      |> Enum.flat_map(fn
        {_role, nil} ->
          []

        {role, file} ->
          case close_file(file.device) do
            :ok -> []
            {:error, cause} -> [%{source: role, filename: file.path, cause: cause}]
          end
      end)

    case failures do
      [] ->
        :ok

      failures ->
        {:error, error(:close_failed, Enum.map(failures, & &1.cause), %{failures: failures})}
    end
  end

  defp close_file(device) do
    File.close(device)
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp error(reason, cause, context), do: Error.new(reason, cause, context)

  defp request_source({:acquire_memo, _path}), do: :memo
  defp request_source({:read_exact, role, _offset, _length}), do: role
  defp request_source({:size, role}), do: role
  defp request_source({:path, role}), do: role

  defp closed_exit?(:normal), do: true
  defp closed_exit?(:noproc), do: true
  defp closed_exit?({:normal, _details}), do: true
  defp closed_exit?({:noproc, _details}), do: true
  defp closed_exit?(_reason), do: false
end
