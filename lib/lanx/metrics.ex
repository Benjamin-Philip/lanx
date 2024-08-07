defmodule Lanx.Metrics do
  @moduledoc false

  alias Lanx.Jobs

  # This module takes care of collecting the metrics for Lanx.
  # It stores this data in standard queueing theory notation.

  def handle_event(
        [:lanx, :execute, :start],
        %{system_time: native_time},
        %{id: id},
        %{jobs: jobs}
      ) do
    time = System.convert_time_unit(native_time, :native, :microsecond)

    Jobs.insert(jobs, %{id: id, system_arrival: time})
  end

  def handle_event(
        [:lanx, :execute, :stop],
        %{duration: native_duration},
        %{id: id},
        %{lanx: lanx, jobs: jobs, expiry: expiry}
      ) do
    duration = System.convert_time_unit(native_duration, :native, :microsecond)
    Jobs.update(jobs, %{id: id, tau: duration, failed?: false})

    Process.send_after(lanx, {:delete_job, id}, expiry)
  end

  def handle_event(
        [:lanx, :execute, :exception],
        %{duration: native_duration},
        %{id: id},
        %{lanx: lanx, jobs: jobs, expiry: expiry}
      ) do
    duration = System.convert_time_unit(native_duration, :native, :microsecond)

    Jobs.update(jobs, %{id: id, tau: duration, failed?: true})

    Process.send_after(lanx, {:delete_job, id}, expiry)
  end

  def handle_event(
        [:lanx, :execute, :worker, :start],
        %{system_time: native_time},
        %{id: id, worker: worker},
        %{jobs: jobs}
      ) do
    time = System.convert_time_unit(native_time, :native, :microsecond)

    Jobs.update(jobs, %{id: id, worker: worker, worker_arrival: time})
  end

  def handle_event(
        [:lanx, :execute, :worker, :stop],
        _,
        %{worker: worker},
        %{lanx: lanx}
      ),
      do: send(lanx, {:assess_worker, worker})
end
