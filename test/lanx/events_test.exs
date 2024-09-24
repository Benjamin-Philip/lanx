defmodule Lanx.EventsTest do
  use ExUnit.Case, async: true

  alias Lanx.EventsTest.TestEvent

  describe "span/2" do
    test "returns a result" do
      assert span() == {:ok, :ok}

      assert span(:raise) ==
               {:exception, %RuntimeError{message: "Failed!"}}
    end

    test "handles starts" do
      span()
      assert_received {:start, time}
      assert is_integer(time)
    end

    test "handles stops" do
      span()

      assert_received {:stop, :ok, duration}
      assert is_integer(duration) and duration > 0
    end

    test "handles exceptions" do
      span(:raise)

      assert_received {:exception, %RuntimeError{message: "Failed!"}, duration}
      assert is_integer(duration) and duration > 0
    end

    test "emits telemetry events" do
      :telemetry.attach_many(
        "test_handler",
        [
          [:lanx, :test, :start],
          [:lanx, :test, :stop],
          [:lanx, :test, :exception]
        ],
        &TestEvent.telemetry_handler/4,
        nil
      )

      span(%{id: "test pass!"})

      assert_received {:telemetry, :start, %{system_time: _systime, monotonic_time: _mtime},
                       %{id: "test pass!"}}

      assert_received {:telemetry, :stop, %{duration: _dur, monotonic_time: _mtime},
                       %{id: "test pass!", end: "stop"}}

      span(%{id: "test raise!"}, :raise)

      assert_received {:telemetry, :exception, %{duration: _dur, monotonic_time: _mtime},
                       %{id: "test raise!", end: "exception"}}
    end
  end

  defp span(), do: span(%{}, [])
  defp span(meta) when is_map(meta), do: span(meta, [])
  defp span(args), do: span(%{}, args)
  defp span(meta, args), do: TestEvent.span(meta, args)

  defmodule TestEvent do
    use Lanx.Events, prefix: [:test]

    def start(_time, :raise), do: raise("Failed!")

    def start(time, _args) do
      send(self(), {:start, time})
      :ok
    end

    def stop(result, duration, _args) do
      send(self(), {:stop, result, duration})
      %{end: "stop"}
    end

    def exception(error, duration, _args) do
      send(self(), {:exception, error, duration})
      %{end: "exception"}
    end

    def telemetry_handler([:lanx, :test, event], measurements, metadata, _config) do
      send(self(), {:telemetry, event, measurements, metadata})
      nil
    end
  end
end
