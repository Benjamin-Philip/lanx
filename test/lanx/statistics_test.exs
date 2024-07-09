defmodule Lanx.StatisticsTest do
  use ExUnit.Case, async: true

  alias Lanx.{Statistics, Helpers}

  describe "delta_c/3" do
    test "returns zero if rho in range" do
      assert Statistics.delta_c(%{rho: 7, c: 10}, {0, 10}, {0.5, 0.8}) == 0
    end

    test "rounds results" do
      # Δc = 2.1212
      assert Statistics.delta_c(%{rho: 8, c: 10}, {5, 20}, {0.4, 0.66}) == 2
      # Δc = 0.66
      assert Statistics.delta_c(%{rho: 8, c: 10}, {5, 20}, {0.4, 0.75}) == 1
      # Δc = -5.0
      assert Statistics.delta_c(%{rho: 2.5, c: 10}, {5, 20}, {0.5, 0.75}) == -5
      # Δc = -1.66
      assert Statistics.delta_c(%{rho: 2.5, c: 10}, {5, 20}, {0.3, 0.75}) == -2
    end

    test "corrects if c prime is out of range" do
      # crosses maximum; c′ = 28
      assert Statistics.delta_c(%{rho: 7, c: 10}, {0, 20}, {0.1, 0.25}) == 10

      # crossess minimum: c′ = 2
      assert Statistics.delta_c(%{rho: 1.6, c: 10}, {5, 10}, {0.8, 0.9}) == -5
    end

    test "handles infinite c_max" do
      assert Statistics.delta_c(%{rho: 7, c: 10}, {0, :infinity}, {0.1, 0.25}) == 18
    end
  end

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
      # Doesn't count on going jobs
      %{id: Helpers.job_id(), system_arrival: time + 1, tau: nil},
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
      # Doesn't count on going jobs
      %{id: Helpers.job_id(), system_arrival: time + 1, tau: nil},
      %{id: Helpers.job_id(), system_arrival: time, tau: 14}
    ]

    lambda = 3
    mu = 3 / 36
    rho = 36

    assert Statistics.assess_system(jobs, 2) == %{lambda: lambda, mu: mu, rho: rho, c: 2}
    assert Statistics.assess_system([], 2) == %{lambda: 0, mu: 0, rho: 0, c: 2}
  end
end
