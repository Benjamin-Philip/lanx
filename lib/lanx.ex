defmodule Lanx do
  @moduledoc """
  Documentation for `Lanx`.
  """

  use GenServer

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
      {:ok, %{pool: opts[:pool], k: opts[:k], pids: pids}}
    end
  end

  @impl true
  def handle_call(:k, _, state) do
    {:reply, length(state.pids), state}
  end
end
