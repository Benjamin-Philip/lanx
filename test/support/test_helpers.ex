defmodule Lanx.TestHelpers do
  def setup_lanx(config) do
    pool_name = Module.concat([LanxTest, config.test, Runner])
    pool = [name: pool_name, min: 0, max: 10, max_concurrency: 1]

    spec =
      {NaiveJQ, [job: fn atom -> :crypto.hash(:sha, Atom.to_string(atom)) end]}

    params = [
      name: config.test,
      pool: pool,
      min: 10,
      spec: spec,
      assess_inter: 1000,
      expiry: 5000
    ]

    lanx = ExUnit.Callbacks.start_supervised!({Lanx, params}, id: config.test)

    %{lanx: lanx, params: params}
  end
end
