defmodule Lanx.MetricsTest do
  use ExUnit.Case, async: false

  alias Lanx.Workers
  alias Lanx.{Metrics, Helpers, Jobs}

  setup config do
    handler = "#{config.test}_handler"
    expiry = 250

    lanx = Lanx.TestHelpers.setup_lanx(config)
    {jobs, workers} = Lanx.tables(config.test)

    # Lanx starts a handler of the same name which we must detach first
    :telemetry.detach(handler)

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
      %{lanx: config.test, jobs: jobs, workers: workers, expiry: expiry}
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    config
    |> Map.merge(lanx)
    |> Map.merge(%{jobs: jobs, workers: workers, expiry: expiry})
  end

  describe "handle_event/4 on system event" do
    test "start adds job", config do
      id = system_execute()
      job = Jobs.lookup(config.jobs, id)

      assert job.id == id
      assert job.system_arrival
    end

    test "stop updates jobs", config do
      id = system_execute()
      job = Jobs.lookup(config.jobs, id)

      refute job.failed?
      assert job.tau
    end

    test "stop schedules job deletion", config do
      system_execute()
      assert Jobs.count(config.jobs) == 1

      Process.sleep(config.expiry + 2)
      assert Jobs.count(config.jobs) == 0
    end

    test "exception updates jobs", config do
      id = Helpers.job_id()

      catch_error(
        :telemetry.span([:lanx, :execute], %{id: id}, fn ->
          raise "Foo!"
        end)
      )

      job = Jobs.lookup(config.jobs, id)

      assert job.failed?
      assert job.tau
    end

    test "exception schedules job deletion", config do
      catch_error(
        :telemetry.span([:lanx, :execute], %{id: Helpers.job_id()}, fn ->
          raise "Foo!"
        end)
      )

      assert Jobs.count(config.jobs) == 1

      Process.sleep(config.expiry + 2)
      assert Jobs.count(config.jobs) == 0
    end
  end

  describe "handle_event/4 on worker" do
    test "start", config do
      id = Helpers.job_id()
      worker = :ets.first(config.workers)
      meta1 = %{id: id}
      meta2 = %{id: id, worker: worker}

      :telemetry.span([:lanx, :execute], meta1, fn ->
        {:telemetry.span([:lanx, :execute, :worker], meta2, fn ->
           {Process.sleep(Enum.random(0..10)), meta2}
         end), meta1}
      end)

      job = Jobs.lookup(config.jobs, id)

      assert job.worker == worker
      assert job.worker_arrival
    end

    test "stop", config do
      id = Helpers.job_id()
      worker = :ets.first(config.workers)
      meta1 = %{id: id}
      meta2 = %{id: id, worker: worker}

      :telemetry.span([:lanx, :execute], meta1, fn ->
        {:telemetry.span([:lanx, :execute, :worker], meta2, fn ->
           {Process.sleep(Enum.random(0..10)), meta2}
         end), meta1}
      end)

      Process.sleep(1)

      worker = Workers.lookup(config.workers, worker)
      assert worker.mu != 0
    end
  end

  defp system_execute(time \\ Enum.random(0..10)) do
    id = Helpers.job_id()
    meta = %{id: id}

    :telemetry.span([:lanx, :execute], meta, fn ->
      {Process.sleep(time), meta}
    end)

    id
  end
end
