defmodule LanxTest do
  use ExUnit.Case, async: true
  doctest Lanx

  alias Lanx.{Helpers, Jobs, Workers}

  setup config do
    Map.merge(config, Lanx.TestHelpers.setup_lanx(config))
  end

  describe "start_link/1" do
    test "starts a Lanx instance", config do
      assert Process.whereis(config.test)
    end

    test "starts a Lanx instance with just defaults", config do
      stop_supervised!(config.test)

      params =
        Keyword.drop(config.params, [:min, :max, :rho_min, :rho_max, :assess_inter, :expiry])

      start_supervised!({Lanx, params})
      assert Process.whereis(config.test)
    end

    test "errors on invalid spec", config do
      assert_raise ArgumentError, fn ->
        Lanx.start_link(Keyword.put(config.params, :spec, "foo"))
      end
    end

    test "errors on invalid pool params", config do
      assert_raise ArgumentError, "invalid pool params, got: \"foo\"", fn ->
        Lanx.start_link(Keyword.put(config.params, :pool, "foo"))
      end
    end

    test "errors on invalid min", config do
      assert_raise ArgumentError, "min must be a whole number, got: \"bar\"", fn ->
        Lanx.start_link(Keyword.put(config.params, :min, "bar"))
      end

      assert_raise ArgumentError, "min must be a whole number, got: -1", fn ->
        Lanx.start_link(Keyword.put(config.params, :min, -1))
      end
    end

    test "errors on invalid max", config do
      assert_raise ArgumentError, "max must be a natural number or :infinity, got: \"bar\"", fn ->
        Lanx.start_link(Keyword.put(config.params, :max, "bar"))
      end

      assert_raise ArgumentError, "max must be a natural number or :infinity, got: -1", fn ->
        Lanx.start_link(Keyword.put(config.params, :max, -1))
      end

      assert_raise ArgumentError, "max must be a natural number or :infinity, got: 0", fn ->
        Lanx.start_link(Keyword.put(config.params, :max, 0))
      end

      assert_raise ArgumentError,
                   "max must be greater than or equal to the min of #{config.params[:min]}, got: 2",
                   fn ->
                     Lanx.start_link(Keyword.put(config.params, :max, 2))
                   end
    end

    test "errors on invalid rho_min", config do
      assert_raise ArgumentError, "rho_min must be a float between 0 and 1, got: \"bar\"", fn ->
        Lanx.start_link(Keyword.put(config.params, :rho_min, "bar"))
      end

      assert_raise ArgumentError, "rho_min must be a float between 0 and 1, got: -1", fn ->
        Lanx.start_link(Keyword.put(config.params, :rho_min, -1))
      end
    end

    test "errors on invalid rho_max", config do
      assert_raise ArgumentError, "rho_max must be a float between 0 and 1, got: \"bar\"", fn ->
        Lanx.start_link(Keyword.put(config.params, :rho_max, "bar"))
      end

      assert_raise ArgumentError, "rho_max must be a float between 0 and 1, got: -1", fn ->
        Lanx.start_link(Keyword.put(config.params, :rho_max, -1))
      end

      assert_raise ArgumentError,
                   "rho_max must be greater than or equal to the rho_min of 0.5, got: 0.1",
                   fn ->
                     Lanx.start_link(Keyword.put(config.params, :rho_max, 0.1))
                   end
    end

    test "errors on invalid expiry", config do
      assert_raise ArgumentError,
                   "expiry must be a natural number in milliseconds, got: \"bar\"",
                   fn ->
                     Lanx.start_link(Keyword.put(config.params, :expiry, "bar"))
                   end

      assert_raise ArgumentError,
                   "expiry must be a natural number in milliseconds, got: -1",
                   fn ->
                     Lanx.start_link(Keyword.put(config.params, :expiry, -1))
                   end

      assert_raise ArgumentError, "expiry must be a natural number in milliseconds, got: 0", fn ->
        Lanx.start_link(Keyword.put(config.params, :expiry, 0))
      end
    end
  end

  describe "init/1" do
    test "exits gracefuly on named process", config do
      stop_supervised!(config.test)

      {mod, jq_params} = config.params[:spec]
      jq_spec = {mod, Keyword.put_new(jq_params, :name, Module.concat([config.test, JQ]))}
      params = Keyword.put(config.params, :spec, jq_spec)

      Process.flag(:trap_exit, true)
      assert {:error, {:shutdown, {_, _, :failed_to_start_node}}} = Lanx.start_link(params)
    end

    test "starts min nodes", config do
      {_, workers} = Lanx.tables(config.test)
      assert Workers.count(workers) == config.params[:min]
    end

    test "correctly creates jobs tables", config do
      {jobs, _} = Lanx.tables(config.test)
      assert :ets.tab2list(jobs) == []
    end

    test "correctly creates workers tables", config do
      {_, workers} = Lanx.tables(config.test)
      workers = :ets.tab2list(workers)

      assert length(workers) == config.params[:min]

      for {id, pid, lambda, mu, rho} <- workers do
        assert String.length(id) == 16
        assert Process.alive?(pid)
        assert lambda == 0
        assert mu == 0
        assert rho == 0
      end
    end

    test "creates persistent_term", config do
      assert :persistent_term.get(config.test, nil)
    end
  end

  describe "terminate/2" do
    test "erases persistent term", config do
      stop_supervised!(config.test)
      refute :persistent_term.get(config.test, nil)
    end
  end

  test "tables/1 returns ets tables", config do
    assert {jobs, workers} = Lanx.tables(config.test)
    assert :ets.info(jobs) != :undefined
    assert :ets.info(workers) != :undefined
  end

  test "expiry/1 returns expiry", config do
    assert Lanx.expiry(config.test) > 0
  end

  test "persisted/1 returns persisted info", config do
    info = Lanx.persisted(config.test)
    assert info.tables == Lanx.tables(config.test)
    assert info.expiry == Lanx.expiry(config.test)
  end

  describe "run/2" do
    test "runs a job", config do
      {_, spec} = config.params[:spec]
      eager_hash = spec[:job].(config.test)
      queued_hash = Lanx.run(config.test, fn pid -> NaiveJQ.run(pid, config.test) end)

      assert queued_hash == eager_hash
    end

    test "inserts job into jobs table", config do
      Lanx.run(config.test, fn pid -> NaiveJQ.run(pid, config.test) end)

      {jobs, _} = Lanx.tables(config.test)
      assert [job] = Jobs.dump(jobs)

      assert job.worker
      assert job.worker_arrival
      assert job.tau != 0
    end

    test "assesses worker", config do
      Lanx.run(config.test, fn pid -> NaiveJQ.run(pid, config.test) end)
      {jobs, workers} = Lanx.tables(config.test)

      Process.sleep(2)

      [%{worker: id}] = Jobs.dump(jobs)
      worker = Workers.lookup(workers, id)

      assert worker.rho != 0
    end

    test "selects least utilized worker", config do
      Lanx.run(config.test, fn pid -> NaiveJQ.run(pid, config.test) end)
      Lanx.run(config.test, fn pid -> NaiveJQ.run(pid, config.test) end)

      {jobs, _} = Lanx.tables(config.test)
      [%{id: id1}, %{id: id2}] = Jobs.dump(jobs)

      assert id1 != id2
    end
  end

  test "metrics/1", config do
    assert Lanx.metrics(config.test) == %{
             lambda: 0,
             mu: 0,
             rho: 0,
             c: config.params[:min]
           }
  end

  describe "assesses" do
    test "metrics on info", config do
      {jobs, workers} = Lanx.tables(config.test)
      worker = :ets.first(workers)
      time = System.convert_time_unit(:erlang.system_time(), :native, :microsecond)

      Jobs.insert(jobs, %{
        id: Helpers.job_id(),
        worker: worker,
        system_arrival: time,
        worker_arrival: time,
        tau: 5
      })

      Jobs.insert(jobs, %{
        id: Helpers.job_id(),
        worker: worker,
        system_arrival: time + 2,
        worker_arrival: time + 2,
        tau: 5
      })

      send(config.test, :assess_metrics)
      Process.sleep(1)

      metrics = Lanx.metrics(config.test)

      assert metrics.lambda == 1
      assert metrics.mu == 0.2
      assert metrics.rho == 5
      assert metrics.c == Workers.count(workers)

      worker = Workers.lookup(workers, worker)

      assert worker.lambda == 1
      assert worker.mu == 0.2
      assert worker.rho == 5
    end

    test "metrics and starts workers if needed", config do
      {jobs, workers} = Lanx.tables(config.test)
      worker = :ets.first(workers)
      time = System.convert_time_unit(:erlang.system_time(), :native, :microsecond)

      Jobs.insert(jobs, %{
        id: Helpers.job_id(),
        worker: worker,
        system_arrival: time,
        worker_arrival: time,
        tau: 10
      })

      Jobs.insert(jobs, %{
        id: Helpers.job_id(),
        worker: worker,
        system_arrival: time + 2,
        worker_arrival: time + 2,
        tau: 10
      })

      send(config.test, :assess_metrics)
      Process.sleep(1)

      c_prime = config.params[:min] + 3
      metrics = Lanx.metrics(config.test)

      assert metrics.lambda == 1
      assert metrics.mu == 0.1
      assert metrics.rho == 10
      assert metrics.c == c_prime
      assert Workers.count(workers) == c_prime
    end

    test "metrics and stops workers if needed", config do
      stop_supervised!(config.test)
      start_supervised!({Lanx, Keyword.put(config.params, :min, 1)}, id: config.test)

      {jobs, workers} = Lanx.tables(config.test)
      worker = :ets.first(workers)
      time = System.convert_time_unit(:erlang.system_time(), :native, :microsecond)

      id1 = Helpers.job_id()
      id2 = Helpers.job_id()

      Jobs.insert(jobs, %{
        id: id1,
        worker: worker,
        system_arrival: time,
        worker_arrival: time,
        tau: 10
      })

      Jobs.insert(jobs, %{
        id: id2,
        worker: worker,
        system_arrival: time + 2,
        worker_arrival: time + 2,
        tau: 10
      })

      # Start extra workers

      send(config.test, :assess_metrics)
      Process.sleep(1)

      metrics = Lanx.metrics(config.test)

      assert metrics.lambda == 1
      assert metrics.mu == 0.1
      assert metrics.rho == 10
      assert metrics.c == 13
      assert Workers.count(workers) == 13

      # Stop extra workers

      Jobs.delete(jobs, id1)
      Jobs.delete(jobs, id2)

      send(config.test, :assess_metrics)
      Process.sleep(1)

      metrics = Lanx.metrics(config.test)

      assert metrics.lambda == 0
      assert metrics.mu == 0
      assert metrics.rho == 0
      assert metrics.c == 1
      assert Workers.count(workers) == 1
    end

    test "workers on info", config do
      {jobs, workers} = Lanx.tables(config.test)
      worker = :ets.first(workers)
      time = System.convert_time_unit(:erlang.system_time(), :native, :microsecond)

      Jobs.insert(jobs, %{id: Helpers.job_id(), worker: worker, worker_arrival: time, tau: 10})

      Jobs.insert(jobs, %{id: Helpers.job_id(), worker: worker, worker_arrival: time + 2, tau: 10})

      send(config.test, :assess_workers)
      Process.sleep(1)
      worker = Workers.lookup(workers, worker)

      assert worker.lambda == 1
      assert worker.mu == 0.1
      assert worker.rho == 10
    end

    test "worker on info", config do
      {jobs, workers} = Lanx.tables(config.test)
      worker = :ets.first(workers)

      send(config.test, {:assess_worker, worker})
      Process.sleep(1)
      assert Process.alive?(config.lanx)

      time = System.convert_time_unit(:erlang.system_time(), :native, :microsecond)

      Jobs.insert(jobs, %{id: Helpers.job_id(), worker: worker, worker_arrival: time, tau: 10})

      Jobs.insert(jobs, %{id: Helpers.job_id(), worker: worker, worker_arrival: time + 2, tau: 10})

      send(config.test, {:assess_worker, worker})
      Process.sleep(1)

      worker = Workers.lookup(workers, worker)

      assert worker.lambda == 1
      assert worker.mu == 0.1
      assert worker.rho == 10
    end
  end
end
