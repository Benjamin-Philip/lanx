defmodule NaiveJQTest do
  use ExUnit.Case, async: true

  setup config do
    params = [name: config.test, job: fn atom -> :crypto.hash(:sha, Atom.to_string(atom)) end]
    naive_jq = start_supervised!({NaiveJQ, params})
    Map.merge(config, %{naive_jq: naive_jq, params: params})
  end

  describe "start_link" do
    test "starts a NaiveJQ instance", config do
      assert Process.whereis(config.test)
    end

    test "starts a unnamed NaiveJQ instance", config do
      assert start_supervised!({NaiveJQ, Keyword.delete(config.params, :name)}, id: :test)
    end

    test "errors on invalid job", config do
      assert_raise ArgumentError, "job must be a function, got: \"foo\"", fn ->
        NaiveJQ.start_link(Keyword.put(config.params, :job, "foo"))
      end
    end
  end

  test "runs job on item", config do
    queued_hash = NaiveJQ.await(config.naive_jq, config.test)
    eager_hash = config.params[:job].(config.test)
    assert queued_hash == eager_hash
  end

  test "doesn't crash on stray run info msg", config do
    send(config.test, :run)
    assert Process.whereis(config.test)
  end
end
