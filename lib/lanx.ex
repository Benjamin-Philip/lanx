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

    * `:min` - The minimun number of workers at any instant. Must be a whole number.

    * `:max` - The maximum number of workers at any instant. Either a natural
      number or `:infinity`. Greater than or equal to`:min`.

    * `:rho_min` - The minimun average worker utilisation at any instant. Must be
      (non inclusively) between 0 and 1.


    * `:rho_max` - The minimun average worker utilisation at any instant. Must be
      (non inclusively) between 0 and 1. Greater than or equal to `:rho_min`.


    * `:assess_inter` - The interval between workers assessments in
      milliseconds.

    * `:expiry` - The time after completion when a job is no longer considered
      in assessments.

  """
  def start_link(opts) do
    opts = validate_opts(opts)
    name = opts[:name]

    {pool_name, pool_spec} = configure_pool(opts)

    supervisor = Module.concat(name, "Supervisor")

    spec = Supervisor.child_spec(opts[:spec], id: :template)

    arg = Keyword.merge(opts, pool: pool_name, spec: spec, expiry: opts[:expiry])

    children = [
      pool_spec,
      %{
        id: __MODULE__,
        start: {GenServer, :start_link, [__MODULE__, arg, [name: name]]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_all, max_restarts: 0, name: supervisor)
  end

  defp validate_opts(opts) do
    opts =
      Keyword.validate!(opts, [
        :name,
        :spec,
        :pool,
        min: 0,
        max: :infinity,
        rho_min: 0.5,
        rho_max: 0.75,
        assess_inter: 1000,
        expiry: 5000
      ])

    Keyword.fetch!(opts, :name)
    Keyword.fetch!(opts, :spec)
    Keyword.fetch!(opts, :pool)

    min = validate_numerical(opts[:min], -1, "min must be a whole number")

    case Keyword.fetch!(opts, :max) do
      val when is_integer(val) and val >= min and val > 0 ->
        val

      val when is_integer(val) and val > 0 ->
        raise ArgumentError,
          message: "max must be greater than or equal to the min of #{min}, got: #{val}"

      :infinity ->
        :infinity

      val ->
        raise ArgumentError,
          message: "max must be a natural number or :infinity, got: #{inspect(val)}"
    end

    rho_min =
      case Keyword.fetch!(opts, :rho_min) do
        val when is_float(val) and val < 1 and val > 0 ->
          val

        val ->
          raise ArgumentError,
            message: "rho_min must be a float between 0 and 1, got: #{inspect(val)}"
      end

    case Keyword.fetch!(opts, :rho_max) do
      val when is_float(val) and val < 1 and val >= rho_min ->
        val

      val when is_float(val) and val < 1 and val > 0 ->
        raise ArgumentError,
          message:
            "rho_max must be greater than or equal to the rho_min of #{rho_min}, got: #{val}"

      val ->
        raise ArgumentError,
          message: "rho_max must be a float between 0 and 1, got: #{inspect(val)}"
    end

    validate_numerical(
      opts[:assess_inter],
      0,
      "assess_inter must be a natural number in milliseconds"
    )

    validate_numerical(opts[:expiry], 0, "expiry must be a natural number in milliseconds")

    opts
  end

  defp validate_numerical(val, gt, msg) do
    case val do
      val when is_integer(val) and val > gt ->
        val

      val ->
        raise ArgumentError, message: msg <> ", got: #{inspect(val)}"
    end
  end

  defp configure_pool(opts) do
    pool = opts[:pool]

    pool_spec =
      try do
        FLAME.Pool.child_spec(
          Keyword.merge(pool, min: opts[:min], max: opts[:max], max_concurrency: 1)
        )
      rescue
        _ -> raise ArgumentError, "invalid pool params, got: #{inspect(pool)}"
      end

    {Keyword.fetch!(pool, :name), pool_spec}
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

    Process.send_after(self(), :assess_metrics, opts[:assess_inter])

    case start_workers(opts[:min], opts[:pool], opts[:spec], workers) do
      :ok ->
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
           spec: opts[:spec],
           min: opts[:min],
           max: opts[:max],
           rho_min: opts[:rho_min],
           rho_max: opts[:rho_max],
           metrics: %{lambda: 0, mu: 0, rho: 0, c: opts[:min]},
           assess_inter: opts[:assess_inter],
           handler: handler
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach(state.handler)
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
    metrics = Statistics.assess_system(jobs, Workers.count(state.workers))

    updates = Statistics.assess_workers(Workers.dump(state.workers), jobs)
    Workers.update(state.workers, updates)

    c_prime =
      case Statistics.delta_c(metrics, {state.min, state.max}, {state.rho_min, state.rho_max}) do
        delta_c when delta_c > 0 ->
          start_workers(delta_c, state.pool, state.spec, state.workers)
          metrics.c + delta_c

        delta_c when delta_c == 0 ->
          metrics.c

        delta_c when delta_c < 0 ->
          stop_workers(-delta_c, state.workers)
          metrics.c + delta_c
      end

    metrics = %{metrics | c: c_prime}

    {:noreply, %{state | metrics: metrics}}
  end

  @impl true
  def handle_info({:assess_worker, worker}, state) do
    updates = Statistics.assess_worker(Jobs.lookup_by_worker(state.jobs, worker))
    Workers.update(state.workers, updates)

    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, :normal}, state) do
    workers = Workers.dump(state.workers)
    filtered = Enum.filter(workers, fn worker -> worker.pid == pid end)

    case filtered do
      [%{id: id, pid: ^pid}] ->
        Workers.delete(state.workers, id)
        {:noreply, state}

      [] ->
        {:noreply, state}
    end
  end

  defp start_workers(c, pool, spec, workers) do
    pids =
      Enum.flat_map(1..c//1, fn _ ->
        result =
          FLAME.place_child(
            pool,
            spec
          )

        case result do
          {:ok, pid} -> [pid]
          _ -> []
        end
      end)

    if length(pids) == c do
      Enum.map(pids, fn pid ->
        Workers.insert(workers, %{id: Helpers.worker_id(), pid: pid})
      end)

      :ok
    else
      {:error, :failed_to_start_node}
    end
  end

  defp stop_workers(c, workers) do
    workers
    |> Workers.least_utilized(c)
    |> Enum.each(fn worker ->
      Workers.delete(workers, worker.id)
      Process.exit(worker.pid, :normal)
    end)

    :ok
  end
end
