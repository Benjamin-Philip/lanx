defmodule Lanx.Statistics do
  @moduledoc false

  @doc """
  Assess all workers given workers and jobs
  """
  def assess_workers(workers, jobs) do
    workers
    |> Enum.map(fn worker ->
      assess_worker(Enum.filter(jobs, fn job -> job.worker == worker.id end))
    end)
    |> Enum.filter(fn update -> update end)
  end

  @doc """
  Assesses a worker given jobs. Assumes all jobs belong to the same worker as
  the first without checking.
  """
  def assess_worker([]), do: nil

  def assess_worker(jobs) do
    [%{worker: id} | _] = jobs
    Map.put(assess(jobs, :worker_arrival), :id, id)
  end

  @doc """
  Assesses the system given jobs.
  """
  def assess_system(jobs), do: assess(jobs, :system_arrival)

  defp assess([], _), do: %{lambda: 0, mu: 0, rho: 0}

  defp assess(jobs, key) do
    n = length(jobs)

    # Let θ be the time between arrivals
    #
    # λ = n/Σθ
    # θ_n = a_n - a_(n - 1), where a_0 = a_1
    # ∴ Σθ = a_n - a_0 = a_n + a_1
    #
    # ∴ λ = n/(a_n + a_1)

    arrivals = jobs |> Enum.map(fn job -> Map.fetch!(job, key) end) |> Enum.sort()

    sigma_theta =
      case Enum.at(arrivals, -1) - Enum.at(arrivals, 0) do
        0 -> 1
        x -> x
      end

    lambda = n / sigma_theta

    sigma_tau =
      case jobs |> Enum.map(fn job -> job.tau end) |> Enum.sum() do
        0 -> 1
        x -> x
      end

    mu = n / sigma_tau

    rho = sigma_tau / sigma_theta
    %{lambda: lambda, mu: mu, rho: rho}
  end
end
