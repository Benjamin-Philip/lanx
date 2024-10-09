defmodule Lanx.Events.Execute do
  @moduledoc false

  use Lanx.Events, prefix: [:execute]

  alias Lanx.{Jobs, Workers}
  alias Lanx.Events.WorkerExecute

  def start(time, {:test, fail?, args}) do
    insert(time, args)

    if fail? do
      raise "Failed!"
    end
  end

  def start(time, args) do
    insert(time, args)
    worker = Workers.least_utilized(args.workers)

    WorkerExecute.span(
      %{id: args.id, worker: worker.id},
      Map.merge(args, %{worker: worker.id, pid: worker.pid})
    )
  end

  def stop(result, duration, {:test, _fail?, args}), do: stop(result, duration, args)

  def stop(_result, duration, %{id: id, lanx: lanx, jobs: jobs, expiry: expiry}) do
    Jobs.update(jobs, %{id: id, tau: duration, failed?: false})
    delete(id, lanx, expiry)

    %{}
  end

  def exception(error, duration, {:test, _fail?, args}), do: exception(error, duration, args)

  def exception(_error, duration, %{id: id, lanx: lanx, jobs: jobs, expiry: expiry}) do
    Jobs.update(jobs, %{id: id, tau: duration, failed?: true})
    delete(id, lanx, expiry)

    %{}
  end

  def insert(time, %{id: id, jobs: jobs}) do
    Jobs.insert(jobs, %{id: id, system_arrival: time})
  end

  def delete(id, lanx, expiry), do: Process.send_after(lanx, {:delete_job, id}, expiry)
end
