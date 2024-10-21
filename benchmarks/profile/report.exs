Benchee.report(
  load: ["benchmarks/profile/saves/*.benchee"],
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}]
)
