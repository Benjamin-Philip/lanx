defmodule Lanx.Workers do
  @moduledoc false

  # Wrapper over the workers ets table
  # {id, pid, lambda, mu, rho}

  @doc """
  Inserts a worker given a map. Inserted workers must have an id.
  """
  def insert(table, worker = %{id: id}) do
    worker =
      Map.merge(
        %{pid: nil, lambda: 0, mu: 0, rho: 0},
        worker
      )

    :ets.insert_new(
      table,
      {id, worker.pid, worker.lambda, worker.mu, worker.rho}
    )
  end

  def insert(_table, job),
    do: raise(ArgumentError, "Workers must have an id, got: #{inspect(job)}")

  @doc """
  Looks up a worker givan a table and id
  """
  def lookup(table, id) do
    [{^id, pid, lambda, mu, rho}] = :ets.lookup(table, id)

    %{
      id: id,
      pid: pid,
      lambda: lambda,
      mu: mu,
      rho: rho
    }
  end

  @doc """
  Updates a job given a map. Updated jobs must have an id.
  """
  def update(table, worker = %{id: id}) do
    worker = Map.merge(lookup(table, id), worker)

    :ets.insert(
      table,
      {id, worker.pid, worker.lambda, worker.mu, worker.rho}
    )
  end

  @doc """
  Deletes a worker given table and id
  """
  def delete(table, id), do: :ets.delete(table, id)

  @doc """
  Counts the number of workers given a table
  """
  # match specification generated with :ets.fun2ms(fn _x -> true end)
  def count(table), do: :ets.select_count(table, [{:"$1", [], [true]}])
end
