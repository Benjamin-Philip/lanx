defmodule Lanx.Events.WorkerExecuteTest do
  use ExUnit.Case, async: true

  alias Lanx.Events.{Execute, WorkerExecute}
  alias Lanx.{Helpers, Jobs, Workers}

  setup config do
    lanx = Lanx.TestHelpers.setup_lanx(config)
    {jobs, workers} = Lanx.tables(config.test)

    id = Helpers.job_id()
    worker = :ets.first(workers)
    meta = %{id: id, worker: worker}

    Execute.insert(System.monotonic_time(), %{id: id, jobs: jobs})

    WorkerExecute.span(
      meta,
      {:test, config.fail?, %{id: id, worker: worker, lanx: config.test, jobs: jobs}}
    )

    job = Jobs.lookup(jobs, id)

    config
    |> Map.merge(lanx)
    |> Map.merge(%{meta | worker: Workers.lookup(workers, worker)})
    |> Map.merge(%{jobs: jobs, workers: workers, job: job})
  end

  @tag fail?: false
  test "start sets job worker", config do
    assert config.job.worker == config.worker.id
    assert config.job.worker_arrival
  end

  @tag fail?: false
  test "stop sets mu", config do
    Process.sleep(3)

    worker = Workers.lookup(config.workers, config.worker.id)
    assert worker.mu != 0
  end

  @tag fail?: true
  test "exception sets mu", config do
    Process.sleep(3)

    worker = Workers.lookup(config.workers, config.worker.id)
    assert worker.mu != 0
  end
end
