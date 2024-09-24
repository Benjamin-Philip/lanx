defmodule Lanx.Events do
  @moduledoc false
  # A behaviour to define spans for events.

  defmacro __using__(prefix: prefix) do
    quote do
      @behaviour Lanx.Events

      def span(start_metadata, args \\ []) when is_map(start_metadata) do
        Lanx.Events.span(__MODULE__, {unquote(prefix), start_metadata}, args)
      end
    end
  end

  @doc """
  Starts an event, and returns its result, given the time and arguments.
  """
  @callback start(time :: integer, args :: term) :: term

  @doc """
  Stops an event and returns the stop metadata, given the event duration and
  arguments.
  """
  @callback stop(result :: term, duration :: pos_integer(), args :: term) :: map()

  @doc """
  Handles an exception in the event and returns the exception metadata, given
  the event duration and arguments.
  """
  @callback exception(error :: Exception.t(), duration :: integer, args :: term) :: map()

  @doc """
  Spans an event, calling `mod.start`, `mod.stop`, `mod.exception` to handle
  starts, stops and exceptions.

  Accepts an event module, a tuple with the telemetry suffix and start metadata,
  and arguments for the callbacks.
  """
  @spec span(mod :: module(), telemetry :: {[atom], map()}, args :: term) :: term
  def span(mod, {event, start_metadata}, args) do
    start_time = System.monotonic_time()
    measurements = %{system_time: System.system_time(), monotonic_time: start_time}
    :telemetry.execute([:lanx] ++ event ++ [:start], measurements, start_metadata)

    try do
      result = mod.start(start_time, args)

      time = System.monotonic_time()
      duration = time - start_time
      metadata = Map.merge(mod.stop(result, duration, args), start_metadata)

      measurements = %{duration: duration, monotonic_time: time}
      :telemetry.execute([:lanx] ++ event ++ [:stop], measurements, metadata)

      {:ok, result}
    rescue
      error ->
        time = System.monotonic_time()
        duration = time - start_time
        metadata = Map.merge(mod.exception(error, duration, args), start_metadata)

        measurements = %{duration: duration, monotonic_time: time}
        :telemetry.execute([:lanx] ++ event ++ [:exception], measurements, metadata)

        {:exception, error}
    end
  end
end
