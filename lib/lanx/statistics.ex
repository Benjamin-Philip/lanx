defmodule Lanx.Statistics do
  @moduledoc false

  @doc """
  Assess all workers given workers and jobs
  """
  def assess_workers(workers, jobs) do
    Enum.map(workers, fn worker ->
      assess_worker(Enum.filter(jobs, fn job -> job.worker == worker.id end))
    end)
  end

  @doc """
  Assesses a worker given jobs. Assumes all jobs belongs to the same worker as
  the first without checking.
  """
  def assess_worker(jobs) do
    jobs = Enum.map(jobs, fn job -> Map.put(job, :system_arrival, job.worker_arrival) end)
    [%{worker: id} | _] = jobs
    Map.put(assess_system(jobs), :id, id)
  end

  @doc """
  Assesses the system given jobs.
  """
  def assess_system(jobs) do
    n = length(jobs)

    # Let θ be the time between arrivals
    #
    # λ = n/Σθ
    # θ_n = a_n - a_(n - 1), where a_0 = a_1
    # ∴ Σθ = a_n - a_0 = a_n + a_1
    #
    # ∴ λ = n/(a_n + a_1)

    arrivals = jobs |> Enum.map(fn job -> job.system_arrival end) |> Enum.sort()
    sigma_theta = Enum.at(arrivals, -1) - Enum.at(arrivals, 0)
    lambda = n / sigma_theta

    sigma_tau = jobs |> Enum.map(fn job -> job.tau end) |> Enum.sum()
    mu = n / sigma_tau

    rho = sigma_tau / sigma_theta
    %{lambda: lambda, mu: mu, rho: rho}
  end
end
