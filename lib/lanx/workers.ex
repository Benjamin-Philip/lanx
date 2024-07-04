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
    table |> :ets.lookup(id) |> hd |> to_map()
  end

  @doc """
  Updates a job given a map or a list of maps. Updated jobs must have an id.
  """
  def update(table, worker = %{id: id}) do
    worker = Map.merge(lookup(table, id), worker)

    :ets.insert(
      table,
      {id, worker.pid, worker.lambda, worker.mu, worker.rho}
    )
  end

  def update(table, updates) when is_list(updates), do: Enum.each(updates, &update(table, &1))
  def update(_table, nil), do: nil

  @doc """
  Deletes a worker given table and id
  """
  def delete(table, id), do: :ets.delete(table, id)

  @doc """
  Counts the number of workers given a table
  """
  # match specification generated with :ets.fun2ms(fn _x -> true end)
  def count(table), do: :ets.select_count(table, [{:"$1", [], [true]}])

  @doc """
  Dumps the contents of the table
  """
  def dump(table) do
    Enum.map(:ets.tab2list(table), &to_map(&1))
  end

  defp to_map(tuple) do
    {id, pid, lambda, mu, rho} = tuple

    %{
      id: id,
      pid: pid,
      lambda: lambda,
      mu: mu,
      rho: rho
    }
  end
end
