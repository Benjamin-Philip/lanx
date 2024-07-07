defmodule Lanx do
  @moduledoc """
  Documentation for `Lanx`.
  """

  use GenServer

  alias Lanx.{Helpers, Statistics, Jobs, Workers, Metrics}

  # Client-side

  @doc """
  Starts a Lanx instance.

  ## Options

    * `:name` - The name of the instance.

    * `:spec` - The spec of the process to be started. Processes must be
      unnamed.

    * `:pool` - The parameters to start the FLAME pool. Overwritten and passed
      through `FLAME.Pool.child_spec/1`.

    * `:k` - The number of servers.

    * `:assess_inter` - The interval between workers assessments in
      milliseconds.

    * `:expiry` - The time after completion when a job is no longer considered
      in assessments.

  """
  def start_link(opts) do
    opts = Keyword.validate!(opts, [:name, :spec, :pool, k: 2, assess_inter: 1000, expiry: 5000])

    validate_natural(opts[:k], "k must be a natural number")
    validate_natural(opts[:assess_inter], "assess_inter must be a natural number in milliseconds")
    validate_natural(opts[:expiry], "expiry must be a natural number in milliseconds")

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

    arg = Keyword.merge(opts, pool: Keyword.fetch!(pool, :name), spec: spec, expiry: expiry)

    children = [
      pool_spec,
      %{
        id: __MODULE__,
        start: {GenServer, :start_link, [__MODULE__, arg, [name: name]]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_all, max_restarts: 0, name: supervisor)
  end

  defp validate_natural(val, msg) do
    case val do
      val when is_integer(val) and val > 0 ->
        val

      val ->
        raise ArgumentError, message: msg <> ", got: #{inspect(val)}"
    end
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
    meta1 = %{id: Helpers.job_id()}

    :telemetry.span([:lanx, :execute], meta1, fn ->
      {_, workers} = Lanx.tables(name)
      worker = Workers.least_utilized(workers)
      meta2 = Map.put(meta1, :worker, worker.id)

      result =
        :telemetry.span([:lanx, :execute, :worker], meta2, fn -> {handler.(worker.pid), meta2} end)

      {result, meta1}
    end)
  end

  @doc """
  Returns the system metrics given a name.
  """
  def metrics(name), do: GenServer.call(name, :metrics)

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
          {:read_concurrency, true}
        ])

      Enum.map(pids, fn pid ->
        Workers.insert(workers, %{id: Helpers.worker_id(), pid: pid})
      end)

      Process.send_after(self(), :assess_metrics, opts[:assess_inter])

      handler = :"#{opts[:name]}_handler"

      :telemetry.attach_many(
        handler,
        [
          [:lanx, :execute, :start],
          [:lanx, :execute, :stop],
          [:lanx, :execute, :exception],
          [:lanx, :execute, :worker, :start],
          [:lanx, :execute, :worker, :stop]
        ],
        &Metrics.handle_event/4,
        %{
          lanx: opts[:name],
          jobs: jobs,
          workers: workers,
          expiry: opts[:expiry]
        }
      )

      Process.flag(:trap_exit, true)

      {:ok,
       %{
         jobs: jobs,
         workers: workers,
         pool: opts[:pool],
         k: opts[:k],
         pids: pids,
         metrics: %{lambda: 0, mu: 0, rho: 0},
         assess_inter: opts[:assess_inter],
         handler: handler
       }}
    end
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler)
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
  def handle_call(:metrics, _, state) do
    {:reply, state.metrics, state}
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

  @impl true
  def handle_info(:assess_workers, state) do
    updates = Statistics.assess_workers(Workers.dump(state.workers), Jobs.dump(state.jobs))
    Workers.update(state.workers, updates)

    {:noreply, state}
  end

  @impl true
  def handle_info(:assess_metrics, state) do
    Process.send_after(self(), :assess_metrics, state.assess_inter)

    jobs = Jobs.dump(state.jobs)
    metrics = Statistics.assess_system(jobs)

    updates = Statistics.assess_workers(Workers.dump(state.workers), jobs)
    Workers.update(state.workers, updates)

    {:noreply, %{state | metrics: metrics}}
  end

  @impl true
  def handle_info({:assess_worker, worker}, state) do
    updates = Statistics.assess_worker(Jobs.lookup_by_worker(state.jobs, worker))
    Workers.update(state.workers, updates)

    {:noreply, state}
  end
end
