Benchee.report(
  load: ["bench/saves/*.benchee"],
  formatters: [
    {Benchee.Formatters.Console, extended_statistics: true},
    {Benchee.Formatters.Markdown, file: "bench/saves/report.md"}
  ]
)
