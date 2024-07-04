defmodule Lanx.WorkersTest do
  use ExUnit.Case, async: true

  alias Lanx.{Workers, Helpers}

  setup config do
    table = :ets.new(config.test, [:set])
    Map.put_new(config, :table, table)
  end

  test "insert/2", config do
    id = Helpers.worker_id()

    Workers.insert(config.table, %{id: id})
    assert :ets.tab2list(config.table) == [{id, nil, 0, 0, 0}]

    invalid = %{pid: self()}

    assert_raise ArgumentError, "Workers must have an id, got: #{inspect(invalid)}", fn ->
      Workers.insert(config.table, invalid)
    end
  end

  test "lookup/2", config do
    worker = %{id: Helpers.worker_id(), pid: self()}
    Workers.insert(config.table, worker)

    merged =
      Map.merge(
        Map.from_keys([:lambda, :mu, :rho], 0),
        worker
      )

    assert Workers.lookup(config.table, worker.id) == merged
  end

  test "update/2", config do
    id = Helpers.worker_id()
    worker = %{id: id, pid: self()}
    Workers.insert(config.table, worker)

    updates = %{
      id: id,
      lambda: 1,
      mu: 2,
      rho: 3
    }

    merged = Map.merge(worker, updates)

    Workers.update(config.table, updates)
    assert Workers.lookup(config.table, id) == merged

    Workers.update(config.table, [updates, updates])
    assert Workers.lookup(config.table, id) == merged

    assert_raise ArgumentError, "Workers must have an id, got: #{inspect(%{})}", fn ->
      Workers.insert(config.table, %{})
    end
  end

  test "delete/2", config do
    id = Helpers.worker_id()
    Workers.insert(config.table, %{id: id})
    Workers.delete(config.table, id)
    assert Workers.count(config.table) == 0
  end

  test "count/1", config do
    Workers.insert(config.table, %{id: Helpers.worker_id()})
    assert Workers.count(config.table) == 1
  end

  test "dump/1", config do
    id = Helpers.worker_id()
    Workers.insert(config.table, %{id: id})

    assert Workers.dump(config.table) == [%{id: id, pid: nil, lambda: 0, mu: 0, rho: 0}]
  end
end
