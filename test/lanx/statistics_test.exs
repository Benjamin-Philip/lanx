defmodule Lanx.StatisticsTest do
  use ExUnit.Case, async: true

  alias Lanx.{Statistics, Helpers}

  test "assess_workers/2" do
    wid1 = Helpers.worker_id()
    worker1 = %{id: wid1}

    wid2 = Helpers.worker_id()
    worker2 = %{id: wid2}

    workers = [worker1, worker2]

    n = 4
    job_ids = Enum.map(0..n, fn _ -> Helpers.job_id() end)

    time = System.convert_time_unit(:erlang.system_time(), :native, :microsecond)

    arrivals =
      Enum.map(0..n, fn i ->
        time + i
      end)

    taus = Enum.map(0..n, fn i -> 10 + 2 * i end)

    jobs =
      Enum.zip([job_ids, arrivals, taus, [wid1, wid1, wid2, wid2]])
      |> Enum.map(fn {id, arrival, tau, worker} ->
        %{id: id, worker: worker, worker_arrival: arrival, tau: tau}
      end)

    lambda1 = 1 / ((0 + 1) / 2)
    mu1 = 1 / ((10 + 12) / 2)
    rho1 = lambda1 / mu1

    lambda2 = 1 / ((0 + 1) / 2)
    mu2 = 1 / ((14 + 16) / 2)
    rho2 = lambda2 / mu2

    statistics =
      [
        %{id: wid1, lambda: lambda1, mu: mu1, rho: rho1},
        %{id: wid2, lambda: lambda2, mu: mu2, rho: rho2}
      ]

    assert Statistics.assess_workers(workers, jobs) == statistics
  end

  test "assess_worker/1" do
    wid = Helpers.worker_id()
    time = System.convert_time_unit(:erlang.system_time(), :native, :microsecond)

    jobs = [
      %{id: Helpers.job_id(), worker: wid, worker_arrival: time, tau: 10},
      %{id: Helpers.job_id(), worker: wid, worker_arrival: time + 1, tau: 12},
      %{id: Helpers.job_id(), worker: wid, worker_arrival: time, tau: 14}
    ]

    lambda = 3
    mu = 3 / 36
    rho = 36

    assert Statistics.assess_worker(jobs) == %{id: wid, lambda: lambda, mu: mu, rho: rho}
    assert Statistics.assess_worker([]) == nil
  end

  test "assess_system/1" do
    time = System.convert_time_unit(:erlang.system_time(), :native, :microsecond)

    jobs = [
      %{id: Helpers.job_id(), system_arrival: time, tau: 10},
      %{id: Helpers.job_id(), system_arrival: time + 1, tau: 12},
      %{id: Helpers.job_id(), system_arrival: time, tau: 14}
    ]

    lambda = 3
    mu = 3 / 36
    rho = 36

    assert Statistics.assess_system(jobs, 2) == %{lambda: lambda, mu: mu, rho: rho, c: 2}
    assert Statistics.assess_system([], 2) == %{lambda: 0, mu: 0, rho: 0, c: 2}
  end
end
