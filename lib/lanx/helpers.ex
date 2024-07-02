defmodule Lanx.Helpers do
  @moduledoc false

  @doc """
  Generates an id for a worker
  """
  def worker_id(), do: :crypto.strong_rand_bytes(10) |> :base64.encode()

  @doc """
  Generates an id for a job
  """
  def job_id(), do: :crypto.strong_rand_bytes(20) |> :base64.encode()
end
