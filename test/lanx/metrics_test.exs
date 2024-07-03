defmodule Lanx.MetricsTest do
  use ExUnit.Case, async: false

  alias Lanx.{Metrics, Helpers, Jobs}

  setup config do
    handler = "#{config.test}-handler"
    expiry = 250

    lanx = Lanx.TestHelpers.setup_lanx(config)
    {jobs, workers} = Lanx.tables(config.test)

    :telemetry.attach_many(
      handler,
      [
        [:lanx, :execute, :start],
        [:lanx, :execute, :stop],
        [:lanx, :execute, :exception]
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
      id1 = system_execute()
      id2 = system_execute()
      Process.sleep(100)
      id3 = system_execute()

      jobs = Enum.map([id1, id2, id3], &Jobs.lookup(config.jobs, &1))

      table_ids = jobs |> Enum.map(&Map.fetch!(&1, :id)) |> Enum.sort()
      ids = [id1, id2, id3] |> Enum.sort()
      assert table_ids == ids

      times = jobs |> Enum.map(&Map.fetch!(&1, :system_arrival)) |> Enum.sort()
      t2 = Enum.at(times, 2)
      t1 = Enum.at(times, 0)
      assert_in_delta t2, t1, 120
    end

    test "stop updates jobs", config do
      id1 = system_execute()
      id2 = system_execute()

      assert Jobs.lookup(config.jobs, id1).failed? == false
      assert Jobs.lookup(config.jobs, id1).failed? == false

      durations =
        [id1, id2] |> Enum.map(&Jobs.lookup(config.jobs, &1).system_arrival) |> Enum.sort()

      t2 = Enum.at(durations, 1)
      t1 = Enum.at(durations, 0)
      assert_in_delta t2, t1, 10
    end

    test "stop schedules job deletion", config do
      system_execute()
      assert Jobs.count(config.jobs) == 1

      Process.sleep(config.expiry + 2)
      assert Jobs.count(config.jobs) == 0
    end

    test "exception updates jobs", config do
      id1 = Helpers.job_id()

      catch_error(
        :telemetry.span([:lanx, :execute], %{id: id1}, fn ->
          raise "Foo!"
        end)
      )

      id2 = Helpers.job_id()

      catch_error(
        :telemetry.span([:lanx, :execute], %{id: id2}, fn ->
          raise "Bar!"
        end)
      )

      assert Jobs.lookup(config.jobs, id1).failed? == true
      assert Jobs.lookup(config.jobs, id1).failed? == true

      durations =
        [id1, id2] |> Enum.map(&Jobs.lookup(config.jobs, &1).system_arrival) |> Enum.sort()

      t2 = Enum.at(durations, 1)
      t1 = Enum.at(durations, 0)
      assert_in_delta t2, t1, 10
    end
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

  defp system_execute(time \\ Enum.random(0..10)) do
    id = Helpers.job_id()
    meta = %{id: id}

    :telemetry.span([:lanx, :execute], meta, fn ->
      {Process.sleep(time), meta}
    end)

    id
  end
end
