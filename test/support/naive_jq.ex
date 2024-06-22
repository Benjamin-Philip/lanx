defmodule NaiveJQ do
  @moduledoc """
  A naive job queue implementation for the sake of testing.
  """

  use GenServer

  def start_link(opts) do
    Keyword.validate!(opts, [:name, :job])

    job =
      case Keyword.fetch!(opts, :job) do
        job when is_function(job) -> job
        job -> raise ArgumentError, message: "job must be a function, got: #{inspect(job)}"
      end

    GenServer.start_link(__MODULE__, job, name: opts[:name])
  end

  def await(server, item) do
    GenServer.call(server, {:await, item})
  end

  @impl true
  def init(job) do
    {:ok, %{job: job, queue: :queue.new()}}
  end

  @impl true
  def handle_call({:await, item}, from, state) do
    appended = :queue.in({item, from}, state.queue)
    send(self(), :run)

    {:noreply, %{state | queue: appended}}
  end

  @impl true
  def handle_info(:run, state) do
    case :queue.out(state.queue) do
      {{:value, {item, from}}, popped} ->
        GenServer.reply(from, state.job.(item))
        {:noreply, %{state | queue: popped}}

      {:empty, _queue} ->
        {:noreply, state}
    end
  end
end
