defmodule Lanx do
  @moduledoc """
  Documentation for `Lanx`.
  """

  use GenServer

  alias Lanx.Helpers

  # Client-side

  @doc """
  Starts a Lanx instance.

  ## Options

    * `:name` - The name of the instance.

    * `:spec` - The spec of the process to be started. Processes must be unnamed.

    * `:pool` - The parameters to start the FLAME pool. Overwritten and passed
      through `FLAME.Pool.child_spec/1`.

    * `:k` - The number of servers.
  """
  def start_link(opts) do
    Keyword.validate!(opts, [:name, :spec, :pool, :k])

    case Keyword.fetch!(opts, :k) do
      k when is_integer(k) and k > 0 -> k
      k -> raise ArgumentError, message: "k must be a natural number, got: #{inspect(k)}"
    end

    pool = Keyword.fetch!(opts, :pool)
    name = Keyword.fetch!(opts, :name)

    supervisor = Module.concat(name, "Supervisor")

    pool_spec =
      try do
        FLAME.Pool.child_spec(pool)
      rescue
        _ -> raise ArgumentError, "invalid pool params, got: #{inspect(pool)}"
      end

    spec = Supervisor.child_spec(Keyword.fetch!(opts, :spec), id: :template)

    arg = opts |> Keyword.put(:pool, Keyword.fetch!(pool, :name)) |> Keyword.put(:spec, spec)

    children = [
      pool_spec,
      %{
        id: __MODULE__,
        start: {GenServer, :start_link, [__MODULE__, arg, [name: name]]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_all, max_restarts: 0, name: supervisor)
  end

  @doc """
  Returns the job and worker ets tables of the Lanx instance given a name.
  """
  def tables(name), do: GenServer.call(name, :tables)

  @doc """
  Runs a job an a server.

  Accepts a lanx instance and an anonymous run function. The run function
  accepts the pid of the assinged server, and handles running the job on the server.
  """
  def run(name, handler) when is_function(handler) do
    :telemetry.span([:lanx, :execute], %{}, fn ->
      pid = GenServer.call(name, :pid)
      meta = %{worker: pid}
      result = :telemetry.span([:lanx, :worker, :execute], meta, fn -> {handler.(pid), meta} end)
      {result, %{}}
    end)
  end

  # Server callbakcs

  @impl true
  def init(opts) do
    pids =
      Enum.flat_map(1..opts[:k], fn _ ->
        result =
          FLAME.place_child(
            opts[:pool],
            opts[:spec]
          )

        case result do
          {:ok, pid} -> [pid]
          _ -> [:error]
        end
      end)

    if Enum.any?(pids, fn element -> element == :error end) do
      {:stop, :failed_to_start_node}
    else
      jobs =
        :ets.new(:"#{opts[:name]}_jobs", [
          :set,
          :public,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])

      workers =
        :ets.new(:"#{opts[:name]}_workers", [
          :set,
          :public,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])

      :ets.insert(workers, Enum.map(pids, fn pid -> {Helpers.worker_id(), pid, 0, 0, 0} end))

      {:ok, %{jobs: jobs, workers: workers, pool: opts[:pool], k: opts[:k], pids: pids}}
    end
  end

  @impl true
  def handle_call(:k, _, state) do
    {:reply, length(state.pids), state}
  end

  @impl true
  def handle_call(:tables, _, state) do
    {:reply, {state.jobs, state.workers}, state}
  end

  @impl true
  def handle_call(:pid, _, state) do
    {:reply, Enum.random(state.pids), state}
  end

  @impl true
  def handle_info({:delete_job, id}, state) do
    Lanx.Jobs.delete(state.jobs, id)
    {:noreply, state}
  end
end
