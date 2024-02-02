[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ],
  locals_without_parens: [
    assert_style: 1,
    assert_style: 2
  ],
  plugins: [Styler],
  styler: [
    {Styler.Style.ModuleDirectives, ignore_prefixes: ["lib/"]},
    {Styler.Style.Pipes, ignore_prefixes: ["test/"]}
  ],
  line_length: 122
]
