defmodule Lanx.Jobs do
  @moduledoc false

  # Wrapper over the jobs ets table
  # {id, worker, system_arrival, worker_arrival, tau, failed?}

  @doc """
  Inserts a job given a map. Inserted jobs must have an id.
  """
  def insert(table, job = %{id: id}) do
    job =
      Map.merge(
        Map.from_keys([:worker, :system_arrival, :worker_arrival, :tau, :failed?], nil),
        job
      )

    :ets.insert_new(
      table,
      {id, job.worker, job.system_arrival, job.worker_arrival, job.tau, job.failed?}
    )
  end

  def insert(_table, job),
    do: raise(ArgumentError, "Jobs must have an id, got: #{inspect(job)}")

  def lookup(table, id) do
    [{^id, worker, system_arrival, worker_arrival, tau, failed?}] = :ets.lookup(table, id)

    %{
      id: id,
      worker: worker,
      system_arrival: system_arrival,
      worker_arrival: worker_arrival,
      tau: tau,
      failed?: failed?
    }
  end

  @doc """
  Updates a job given a map. Updated jobs must have an id.
  """
  def update(table, job = %{id: id}) do
    job = Map.merge(lookup(table, id), job)

    :ets.insert(
      table,
      {id, job.worker, job.system_arrival, job.worker_arrival, job.tau, job.failed?}
    )
  end

  def update(_table, job),
    do: raise(ArgumentError, "Jobs must have an id, got: #{inspect(job)}")

  @doc """
  Deletes a job given table and id
  """
  def delete(table, id), do: :ets.delete(table, id)

  @doc """
  Counts the number of jobs given a table
  """
  # match specification generated witb ets:fun2ms/1
  def count(table), do: :ets.select_count(table, [{:"$1", [], [true]}])
end
