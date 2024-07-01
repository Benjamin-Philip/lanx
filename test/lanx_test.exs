defmodule LanxTest do
  use ExUnit.Case, async: true
  doctest Lanx

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

    test "foo test", config do
      Enum.each(0..10, fn _ ->
        Lanx.run(config.test, fn pid -> NaiveJQ.run(pid, :"#{:rand.normal()}") end)
      end)
    end
  end
end
