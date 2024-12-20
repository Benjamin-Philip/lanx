# A profile/benchmark to evaluate Lanx's overhead.
#
# profiles running a rand + encode function on:
#
# 1. As is
# 2. NaiveJQ
# 3. FLAME
# 4. Lanx (on NaiveJQ)
#
# # Options
#
# --tag [string]    tag name
# --profile         profile with eprof

defmodule RandEncode do
  def encode do
    Base.encode64(:crypto.strong_rand_bytes(2 ** 5))
  end
end

Supervisor.start_link(
  [
    {NaiveJQ, [name: RandJQ, job: fn _ -> RandEncode.encode() end]},
    {FLAME.Pool, name: FLAMECallRunner, min: 1, max: 1, max_concurrency: 1},
    {FLAME.Pool, name: FLAMEJQRunner, min: 1, max: 1, max_concurrency: 1},
    {Lanx,
     [
       name: RandLanx,
       pool: [name: LanxRunner, min: 1, max: 1, max_concurrency: 1],
       min: 1,
       max: 1,
       spec: {NaiveJQ, [job: fn _ -> RandEncode.encode() end]}
     ]}
  ],
  strategy: :one_for_one
)

FLAME.place_child(FLAMEJQRunner, {NaiveJQ, [name: FLAMEJQ, job: fn _ -> RandEncode.encode() end]})

opts =
  case OptionParser.parse(System.argv(), switches: [tag: :string, profile: :boolean]) do
    {opts, _, _} -> opts
    _ -> []
  end

path = "bench/saves/#{System.system_time()}.benchee"

save_opts =
  case opts[:tag] do
    nil -> %{path: path}
    tag -> %{path: path, tag: tag}
  end

Benchee.run(
  %{
    "encode" => &RandEncode.encode/0,
    "NaiveJQ" => fn -> NaiveJQ.run(RandJQ, System.system_time()) end,
    "FLAMECall" => fn -> FLAME.call(FLAMECallRunner, &RandEncode.encode/0) end,
    "FLAMEJQ" => fn -> NaiveJQ.run(FLAMEJQ, System.system_time()) end,
    "Lanx" => fn -> Lanx.run(RandLanx, fn pid -> NaiveJQ.run(pid, System.system_time()) end) end
  },
  profile_after:
    if opts[:profile] do
      :eprof
    else
      false
    end,
  time: 10,
  save: save_opts,
  formatters: []
)
