# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.ConfigurableTest do
  use Styler.StyleCase, async: true, filename: "lib/test.exs"

  describe "configurable" do
    test "filename prefix is ignored" do
      Styler.Config.set!(
        enabled_styles: [
          {Styler.Style.Pipes, ignore_prefixes: ["lib/"]}
        ]
      )

      assert_style("f(g(h(x))) |> j()", "f(g(h(x))) |> j()")

      Styler.Config.set!([])
    end

    test "filename prefix is ignored, multiple prefixes" do
      Styler.Config.set!(
        enabled_styles: [
          {Styler.Style.Pipes, ignore_prefixes: ["test/", "lib/"]}
        ]
      )

      assert_style("f(g(h(x))) |> j()", "f(g(h(x))) |> j()")

      Styler.Config.set!([])
    end

    test "filename not in prefix is styled" do
      Styler.Config.set!(
        enabled_styles: [
          {Styler.Style.Pipes, ignore_prefixes: ["test/"]}
        ]
      )

      assert_style("f(g(h(x))) |> j()", "x |> h() |> g() |> f() |> j()")
      Styler.Config.set!([])
    end

    test "if style is not present, no changes are made" do
      Styler.Config.set!(enabled_styles: [])

      assert_style("f(g(h(x))) |> j()", "f(g(h(x))) |> j()")
      Styler.Config.set!([])
    end
  end
end
