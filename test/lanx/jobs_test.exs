defmodule Lanx.JobsTest do
  use ExUnit.Case, async: true

  alias Lanx.{Jobs, Helpers}

  setup config do
    table = :ets.new(config.test, [:set])
    Map.put_new(config, :table, table)
  end

  test "insert/2", config do
    id = Helpers.job_id()
    time = :erlang.system_time()

    Jobs.insert(config.table, %{
      id: id,
      system_arrival: time
    })

    assert :ets.tab2list(config.table) == [{id, nil, time, nil, nil, nil}]

    invalid = %{system_arrival: time}

    assert_raise ArgumentError, "Jobs must have an id, got: #{inspect(invalid)}", fn ->
      Jobs.insert(config.table, invalid)
    end
  end

  test "lookup/2", config do
    job = %{id: Helpers.job_id(), system_arrival: :erlang.system_time()}
    Jobs.insert(config.table, job)

    merged =
      Map.merge(
        Map.from_keys([:worker, :system_arrival, :worker_arrival, :tau, :failed?], nil),
        job
      )

    assert Jobs.lookup(config.table, job.id) == merged
  end

  test "lookup_by_worker/2", config do
    worker = Helpers.worker_id()
    job = %{id: Helpers.job_id(), worker: worker, system_arrival: :erlang.system_time()}
    Jobs.insert(config.table, job)

    merged =
      Map.merge(
        Map.from_keys([:worker, :system_arrival, :worker_arrival, :tau, :failed?], nil),
        job
      )

    assert Jobs.lookup_by_worker(config.table, worker) == [merged]
  end

  test "update/2", config do
    id = Helpers.job_id()
    time = :erlang.system_time()
    job = %{id: id, system_arrival: time}
    Jobs.insert(config.table, job)

    updates = %{
      id: id,
      worker: self(),
      worker_arrival: time,
      tau: time,
      failed?: false
    }

    Jobs.update(config.table, updates)
    assert Jobs.lookup(config.table, id) == Map.merge(job, updates)

    assert_raise ArgumentError, "Jobs must have an id, got: #{inspect(%{})}", fn ->
      Jobs.insert(config.table, %{})
    end
  end

  test "delete/2", config do
    id = Helpers.job_id()
    Jobs.insert(config.table, %{id: id})
    Jobs.delete(config.table, id)
    assert Jobs.count(config.table) == 0
  end

  test "count/1", config do
    Jobs.insert(config.table, %{id: Helpers.job_id()})
    assert Jobs.count(config.table) == 1
  end

  test "dump/1", config do
    id = Helpers.job_id()
    time = :erlang.system_time()

    Jobs.insert(config.table, %{
      id: id,
      system_arrival: time
    })

    assert Jobs.dump(config.table) == [
             %{
               id: id,
               worker: nil,
               system_arrival: time,
               worker_arrival: nil,
               tau: nil,
               failed?: nil
             }
           ]
  end
end
