# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler do
  @moduledoc """
  Styler is a formatter plugin with stronger opinions on code organization, multi-line defs and other code-style matters.
  """
  @behaviour Mix.Tasks.Format

  alias Mix.Tasks.Format
  alias Styler.StyleError
  alias Styler.Zipper

  @styles [
    Styler.Style.ModuleDirectives,
    Styler.Style.Pipes,
    Styler.Style.SingleNode,
    Styler.Style.Defs,
    Styler.Style.Blocks,
    Styler.Style.Deprecations,
    Styler.Style.Configs
  ]

  @doc false
  def style({ast, comments}, file, opts) do
    on_error = opts[:on_error] || :log
    Styler.Config.set(opts)
    zipper = Zipper.zip(ast)

    enabled_styles = Styler.Config.get(:enabled_styles) || @styles

    {{ast, _}, comments} =
      enabled_styles
      |> Enum.filter(fn
        {_style, opts} ->
          if Keyword.has_key?(opts, :ignore_prefixes) do
            file = Path.join(File.cwd!(), file)

            found =
              opts[:ignore_prefixes]
              |> Enum.map(&Path.join(File.cwd!(), &1))
              |> Enum.any?(&String.starts_with?(file, &1))

            !found
          else
            true
          end

        _style ->
          true
      end)
      |> Enum.map(fn
        {style, _opts} -> style
        style -> style
      end)
      |> Enum.reduce({zipper, comments}, fn style, {zipper, comments} ->
        context = %{comments: comments, file: file}

        try do
          {zipper, %{comments: comments}} = Zipper.traverse_while(zipper, context, &style.run/2)
          {zipper, comments}
        rescue
          exception ->
            exception = StyleError.exception(exception: exception, style: style, file: file)

            if on_error == :log do
              error = Exception.format(:error, exception, __STACKTRACE__)
              Mix.shell().error("#{error}\n#{IO.ANSI.reset()}Skipping style and continuing on")
              {zipper, context}
            else
              reraise exception, __STACKTRACE__
            end
        end
      end)

    {ast, comments}
  end

  @impl Format
  def features(_opts), do: [sigils: [], extensions: [".ex", ".exs"]]

  @doc """
  Options is a list of styles, that can have options, à la credo:

  Example `.formatter.exs`:

  [
    plugins: [Styler],
    styler: [
      enabled_styles: [
        {Styler.Style.ModuleDirectives, ignore_prefixes: ["lib/"]},
        {Styler.Style.Pipes, ignore_prefixes: ["test/"]},
      ]
    ]
  ]

  For now, the only config is `ignore_prefixes`, which is a list of file
  prefixes to ignore when styling.
  """
  @impl Format
  def format(input, formatter_opts) do
    file = formatter_opts[:file]
    styler_opts = formatter_opts[:styler] || []

    {ast, comments} =
      input
      |> string_to_quoted_with_comments(to_string(file))
      |> style(file, styler_opts)

    quoted_to_string(ast, comments, formatter_opts)
  end

  @doc false
  # Wrap `Code.string_to_quoted_with_comments` with our desired options
  def string_to_quoted_with_comments(code, file \\ "nofile") when is_binary(code) do
    Code.string_to_quoted_with_comments!(code,
      literal_encoder: &__MODULE__.literal_encoder/2,
      token_metadata: true,
      unescape: false,
      file: file
    )
  end

  @doc false
  def literal_encoder(literal, meta), do: {:ok, {:__block__, meta, [literal]}}

  @doc false
  # Turns an ast and comments back into code, formatting it along the way.
  def quoted_to_string(ast, comments, formatter_opts \\ []) do
    opts = [{:comments, comments}, {:escape, false} | formatter_opts]
    {line_length, opts} = Keyword.pop(opts, :line_length, 122)

    formatted =
      ast
      |> Code.quoted_to_algebra(opts)
      |> Inspect.Algebra.format(line_length)

    IO.iodata_to_binary([formatted, ?\n])
  end
end
