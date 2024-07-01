defmodule Lanx.MetricsTest do
  use ExUnit.Case, async: false

  alias Lanx.{Metrics, Helpers}

  setup config do
    handler = "#{config.test}-handler"
    expiry = 250

    :telemetry.attach_many(
      handler,
      [
        [:lanx, :execute, :start],
        [:lanx, :execute, :stop],
        [:lanx, :execute, :exception]
      ],
      &Metrics.handle_event/4,
      %{lanx: config.test, expiry: expiry}
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    lanx = Lanx.TestHelpers.setup_lanx(config)
    {jobs, workers} = Lanx.tables(config.test)

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

      jobs = :ets.match(config.jobs, {:"$0", :_, :"$1", :_, :_})

      table_ids = jobs |> Enum.map(&Enum.at(&1, 0)) |> Enum.sort()
      ids = [id1, id2, id3] |> Enum.sort()
      assert table_ids == ids

      times = jobs |> Enum.map(&Enum.at(&1, 1)) |> Enum.sort()
      t2 = Enum.at(times, 2)
      t1 = Enum.at(times, 0)
      assert_in_delta t2, t1, 120
    end

    test "start schedules job deletion", config do
      system_execute()
      assert length(:ets.tab2list(config.jobs)) == 1

      Process.sleep(config.expiry)
      assert length(:ets.tab2list(config.jobs)) == 0
    end

    test "start job deletion doesn't timeout jobs", config do
      system_execute(750)
      assert length(:ets.tab2list(config.jobs)) == 1

      # TODO: Fix race conditions in test
      # Process.sleep(config.expiry)
      assert length(:ets.tab2list(config.jobs)) == 1

      Process.sleep(config.expiry)
      assert length(:ets.tab2list(config.jobs)) == 0
    end

    test "stop updates jobs", config do
      system_execute()
      system_execute()

      durations =
        :ets.match(config.jobs, {:_, :_, :_, :"$0", :_}) |> List.flatten() |> Enum.sort()

      t2 = Enum.at(durations, 1)
      t1 = Enum.at(durations, 0)
      assert_in_delta t2, t1, 10
    end

    test "exception updates jobs", config do
      catch_error(
        :telemetry.span([:lanx, :execute], %{id: Helpers.job_id()}, fn ->
          raise "Foo!"
        end)
      )

      catch_error(
        :telemetry.span([:lanx, :execute], %{id: Helpers.job_id()}, fn ->
          raise "Bar!"
        end)
      )

      durations =
        :ets.match(config.jobs, {:_, :_, :_, :_, :"$0"}) |> List.flatten() |> Enum.sort()

      t2 = Enum.at(durations, 1)
      t1 = Enum.at(durations, 0)
      assert_in_delta t2, t1, 10
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
