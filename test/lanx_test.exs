defmodule LanxTest do
  alias Lanx.Workers
  alias Lanx.Jobs
  use ExUnit.Case, async: true
  doctest Lanx

  alias Lanx.Helpers

  setup config do
    Map.merge(config, Lanx.TestHelpers.setup_lanx(config))
  end

  describe "start_link/1" do
    test "starts a Lanx instance", config do
      assert Process.whereis(config.test)
    end

    test "starts k nodes", config do
      assert GenServer.call(config.test, :k) == config.params[:k]
    end

    test "correctly creates jobs tables", config do
      {jobs, _} = Lanx.tables(config.test)
      assert :ets.tab2list(jobs) == []
    end

    test "correctly creates workers tables", config do
      {_, workers} = Lanx.tables(config.test)
      workers = :ets.tab2list(workers)

      assert length(workers) == config.params[:k]

      for {id, pid, lambda, mu, rho} <- workers do
        assert String.length(id) == 16
        assert Process.alive?(pid)
        assert lambda == 0
        assert mu == 0
        assert rho == 0
      end
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

    test "errors on invalid k", config do
      assert_raise ArgumentError, "k must be a natural number, got: \"bar\"", fn ->
        Lanx.start_link(Keyword.put(config.params, :k, "bar"))
      end

      assert_raise ArgumentError, "k must be a natural number, got: -1", fn ->
        Lanx.start_link(Keyword.put(config.params, :k, -1))
      end

      assert_raise ArgumentError, "k must be a natural number, got: 0", fn ->
        Lanx.start_link(Keyword.put(config.params, :k, 0))
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

    test "starts tables", config do
      {jobs, workers} = Lanx.tables(config.test)
      assert Lanx.Jobs.count(jobs)
      assert Lanx.Workers.count(workers) == config.params[:k]
    end
  end

  test "tables/2 returns ets tables", config do
    assert {jobs, workers} = Lanx.tables(config.test)
    assert :ets.info(jobs) != :undefined
    assert :ets.info(workers) != :undefined
  end

  describe "run/2" do
    test "runs a job", config do
      {_, spec} = config.params[:spec]
      eager_hash = spec[:job].(config.test)
      queued_hash = Lanx.run(config.test, fn pid -> NaiveJQ.run(pid, config.test) end)

      assert queued_hash == eager_hash
    end
  end

  test "assesses workers on info", config do
    {jobs, workers} = Lanx.tables(config.test)
    worker = :ets.first(workers)
    time = System.convert_time_unit(:erlang.system_time(), :native, :millisecond)

    Jobs.insert(jobs, %{id: Helpers.job_id(), worker: worker, worker_arrival: time, tau: 10})
    Jobs.insert(jobs, %{id: Helpers.job_id(), worker: worker, worker_arrival: time + 2, tau: 10})

    send(config.test, :assess_workers)
    Process.sleep(10)
    worker = Workers.lookup(workers, worker)

    assert worker.lambda == 1
    assert worker.mu == 0.1
    assert worker.rho == 10
  end
end
