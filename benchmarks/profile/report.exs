Benchee.report(
  load: ["benchmarks/profile/saves/*.benchee"],
  formatters: [
    {Benchee.Formatters.Console, extended_statistics: true},
    {Benchee.Formatters.Markdown, file: "benchmarks/profile/saves/report.md"}
  ]
)
