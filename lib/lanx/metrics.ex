defmodule Lanx.Metrics do
  @moduledoc false

  # This module takes care of collecting the metrics for Lanx.
  # It stores this data in standard queueing theory notation.

  # @doc """
  # Returns all the system metrics given a pid.
  # """

  # def system(pid), do: Agent.get(pid, fn metrics -> metrics end)
  #
  def handle_event(
        [:lanx, :execute, :start],
        %{system_time: native_time},
        %{id: id},
        %{jobs: jobs}
      ) do
    time = System.convert_time_unit(native_time, :native, :millisecond)

    :ets.insert_new(jobs, {id, nil, time, nil, nil})
  end

  def handle_event(
        [:lanx, :execute, :stop],
        %{duration: native_duration},
        %{id: id},
        %{lanx: lanx, jobs: jobs, expiry: expiry}
      ) do
    duration = System.convert_time_unit(native_duration, :native, :millisecond)

    [{id, worker, time, nil, nil}] = :ets.lookup(jobs, id)
    :ets.insert(jobs, {id, worker, time, duration, nil})

    Process.send_after(lanx, {:delete_job, id, expiry}, expiry)
  end

  def handle_event(
        [:lanx, :execute, :exception],
        %{duration: native_duration},
        %{id: id},
        %{jobs: jobs}
      ) do
    duration = System.convert_time_unit(native_duration, :native, :millisecond)

    [{id, worker, time, nil, nil}] = :ets.lookup(jobs, id)
    :ets.insert(jobs, {id, worker, time, nil, duration})
  end
end
