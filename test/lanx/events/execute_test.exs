defmodule Lanx.Events.ExecuteTest do
  use ExUnit.Case, async: true

  alias Lanx.Events.Execute
  alias Lanx.{Helpers, Jobs}

  setup config do
    expiry = 250

    lanx = Lanx.TestHelpers.setup_lanx(config)
    {jobs, workers} = Lanx.tables(config.test)

    id = system_execute(config.test, jobs, expiry, config.fail?)
    job = Jobs.lookup(jobs, id)

    config
    |> Map.merge(lanx)
    |> Map.merge(%{jobs: jobs, workers: workers, expiry: expiry, id: id, job: job})
  end

  @tag fail?: false
  test "start adds job", config do
    assert config.job.id == config.id
    assert config.job.system_arrival
  end

  describe "stop" do
    @describetag fail?: false

    test "updates jobs", config do
      refute config.job.failed?
      assert config.job.tau
    end

    test "schedules job deletion", config do
      assert Jobs.count(config.jobs) == 1

      Process.sleep(config.expiry + 2)
      assert Jobs.count(config.jobs) == 0
    end
  end

  describe "exception" do
    @describetag fail?: true
    test "updates jobs", config do
      assert config.job.failed?
      assert config.job.tau
    end

    test "schedules job deletion", config do
      assert Jobs.count(config.jobs) == 1

      Process.sleep(config.expiry + 2)
      assert Jobs.count(config.jobs) == 0
    end
  end

  defp system_execute(lanx, jobs, expiry, fail?) do
    id = Helpers.job_id()
    Execute.span(%{id: id}, {:test, fail?, %{id: id, lanx: lanx, jobs: jobs, expiry: expiry}})

    id
  end
end
