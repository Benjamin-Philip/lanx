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

    GenServer.start_link(__MODULE__, job, Keyword.delete(opts, :job))
  end

  def run(server, item) do
    GenServer.call(server, {:run, item})
  end

  @impl true
  def init(job) do
    {:ok, %{job: job, queue: :queue.new()}}
  end

  @impl true
  def handle_call({:run, item}, from, state) do
    appended = :queue.in({item, from}, state.queue)
    send(self(), :execute)

    {:noreply, %{state | queue: appended}}
  end

  @impl true
  def handle_info(:execute, state) do
    case :queue.out(state.queue) do
      {{:value, {item, from}}, popped} ->
        GenServer.reply(from, state.job.(item))
        {:noreply, %{state | queue: popped}}

      {:empty, _queue} ->
        {:noreply, state}
    end
  end
end
