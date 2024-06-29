defmodule LanxTest do
  use ExUnit.Case, async: true
  doctest Lanx

  setup config do
    pool_name = Module.concat([LanxTest, config.test, Runner])
    pool = [name: pool_name, min: 0, max: 10, max_concurrency: 1]

    spec =
      {NaiveJQ, [job: fn atom -> :crypto.hash(:sha, Atom.to_string(atom)) end]}

    params = [name: config.test, pool: pool, k: 10, spec: spec]
    lanx = start_supervised!({Lanx, params}, id: config.test)
    Map.merge(config, %{lanx: lanx, params: params})
  end

  describe "start_link" do
    test "starts a Lanx instance", config do
      assert Process.whereis(config.test)
    end

    test "starts k nodes", config do
      assert GenServer.call(config.test, :k) == config.params[:k]
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
end
