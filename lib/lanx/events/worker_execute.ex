defmodule Lanx.Events.WorkerExecute do
  @moduledoc false

  use Lanx.Events, prefix: [:worker, :execute]

  alias Lanx.Jobs

  def start(time, {:test, fail?, args}) do
    update(args.jobs, args.id, args.worker, time)

    if fail? do
      raise "Failed!"
    end
  end

  def start(time, args) do
    update(args.jobs, args.id, args.worker, time)
    args.handler.(args.pid)
  end

  def stop(result, duration, {:test, fail?, args}) do
    Jobs.update(args.jobs, %{id: args.id, tau: duration, failed?: fail?})
    stop(result, duration, args)
  end

  def stop(_result, _duration, args) do
    send(args.lanx, {:assess_worker, args.worker})

    %{}
  end

  def exception(error, duration, args), do: stop(error, duration, args)

  def update(jobs, id, worker, time),
    do: Jobs.update(jobs, %{id: id, worker: worker, worker_arrival: time})
end
