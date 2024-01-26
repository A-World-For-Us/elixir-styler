# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.PipesTest do
  use Styler.StyleCase, async: true

  describe "big picture" do
    test "unnests multiple steps" do
      assert_style("f(g(h(x))) |> j()", "x |> h() |> g() |> f() |> j()")
    end

    test "doesn't modify valid pipe" do
      assert_style("""
      a()
      |> b()
      |> c()

      a |> b() |> c()
      """)
    end

    test "extracts >0 arity functions" do
      assert_style(
        """
        M.f(a, b)
        |> g()
        |> h()
        """,
        """
        a
        |> M.f(b)
        |> g()
        |> h()
        """
      )
    end
  end

  describe "block pipe starts" do
    test "parent is a function invocation" do
      assert_style(
        "a(if x do y end |> foo(), b)",
        """
        a(
          foo(
            if x do
              y
            end
          ),
          b
        )
        """
      )
    end

    test "handles arbitrary do-block macros" do
      assert_style("""
      IO.puts(
        foo meow do
          :foo
        end
      )
      """)

      assert_style("""
      foo do
        "foo"
      end
      |> IO.puts()
      """)

      assert_style("""
      foo meow? do
        :meow
      else
        :bark
      end
      |> IO.puts()
      """)
    end

    test "block extraction: names aliased modules" do
      assert_style("""
      Foo.bar do
        :ok
      end
      |> case do
        :ok -> :ok
        _ -> :error
      end
      """)
    end

    test "macro with arg and do block" do
      assert_style("""
      "baz"
      |> foo do
        "foo"
      end
      |> IO.puts()
      """)
    end

    test "variable assignment of a block" do
      assert_style(
        """
        x =
          case y do
            :ok -> :ok |> IO.puts()
          end
          |> bar()
          |> baz()
        """,
        """
        x =
          case y do
            :ok -> IO.puts(:ok)
          end
          |> bar()
          |> baz()
        """
      )
    end

    test "keeps fors" do
      assert_style("""
      for(a <- as, do: a)
      |> bar()
      """)
    end

    test "keeps unless" do
      assert_style("""
      unless foo do
        bar
      end
      |> wee()
      """)
    end

    test "keeps with" do
      assert_style("""
      with({:ok, value} <- foo(), do: value)
      |> bar()
      """)
    end

    test "keeps conds" do
      assert_style("""
      cond do
        x -> :ok
      end
      |> foo()
      """)
    end

    test "keeps case" do
      assert_style("""
      case x do
        x -> x
      end
      |> foo()
      """)
    end

    test "keeps if" do
      assert_style("""
      if true do
        nil
      end
      |> foo()
      """)
    end

    test "keeps quote" do
      assert_style("""
      quote do
        foo
      end
      |> foo()
      """)
    end
  end

  describe "single pipe issues" do
    test "allows unquote single pipes" do
      assert_style("foo |> unquote(bar)")
    end

    test "fixes simple single pipes" do
      assert_style("b(a) |> c()", "a |> b() |> c()")
      assert_style("a |> f()", "f(a)")
      assert_style("x |> bar", "bar(x)")
      assert_style("def a, do: b |> c()", "def a, do: c(b)")
    end

    test "keeps invocation on a single line" do
      assert_style(
        """
        foo
        |> bar(baz, bop, boom)
        """,
        """
        bar(foo, baz, bop, boom)
        """
      )

      assert_style(
        """
        foo
        |> bar(baz)
        """,
        """
        bar(foo, baz)
        """
      )

      assert_style(
        """
        def halt(exec, halt_message) do
          %__MODULE__{exec | halted: true}
          |> put_halt_message(halt_message)
        end
        """,
        """
        def halt(exec, halt_message) do
          put_halt_message(%__MODULE__{exec | halted: true}, halt_message)
        end
        """
      )

      assert_style(
        """
        if true do
          false
        end
        |> foo(
          bar
        )
        """,
        """
        if true do
          false
        end
        |> foo(bar)
        """
      )
    end
  end

  describe "valid pipe starts & unpiping" do
    test "writes brackets for unpiped kwl" do
      assert_style("foo(kwl: :arg) |> bar()", "[kwl: :arg] |> foo() |> bar()")
      assert_style("%{a: foo(a: :b, c: :d) |> bar()}", "%{a: [a: :b, c: :d] |> foo() |> bar()}")
      assert_style("%{a: foo([a: :b, c: :d]) |> bar()}", "%{a: [a: :b, c: :d] |> foo() |> bar()}")
    end

    test "allows fn" do
      assert_style("""
      fn
        :ok -> :ok
        :error -> :error
      end
      |> b()
      |> c()
      """)
    end

    test "recognizes infix ops as valid pipe starts" do
      assert_style("(bar() == 1) |> foo()", "foo(bar() == 1)")
      assert_style("(x in 1..100) |> foo()", "foo(x in 1..100)")
    end

    test "0 arity is just fine!" do
      assert_style("foo() |> bar() |> baz()")
      assert_style("Module.foo() |> bar() |> baz()")
    end

    test "ecto funtimes" do
      for from <- ~w(from Query.from Ecto.Query.from) do
        assert_style("""
        #{from}(foo in Bar, where: foo.bool)
        |> some_query_helper()
        |> Repo.all()
        """)
      end

      for from <- ~w(from Query.from Ecto.Query.from) do
        assert_style("""
        #{from}(foo in Bar, where: foo.bool)
        |> Repo.all()
        """)
      end

      assert_style("SomeModule |> where([sm], not sm.archived)")
      assert_style("base_query() |> not_hidden_query()")
      assert_style("query |> where([sm], not sm.archived)")

      assert_style("^foo |> Ecto.Query.bar() |> Ecto.Query.baz()")
    end

    test "ex_machina" do
      assert_style("insert(:user) |> with_password()")
      assert_style("insert(:user) |> with_password() |> Repo.insert()")
      assert_style("build(:user) |> with_password()")
      assert_style("build(:user) |> with_password() |> Repo.insert()")
      assert_style("build_list(11, :user) |> Enum.map()")
    end

    test "ranges" do
      assert_style("start..stop//step |> foo()", "foo(start..stop//step)")
      assert_style("start..stop//step |> foo() |> bar()")
      assert_style("foo(start..stop//step) |> bar()", "start..stop//step |> foo() |> bar()")
    end
  end

  describe "multiline as a first pipe" do
    test "multiline is left alone" do
      # assert_style("""
      # %{
      #   foo: "bar",
      #   bar: "foo"
      # }
      # |> bar()
      # """)

      # assert_style("""
      # %Struct{
      #   foo: "bar",
      #   bar: "foo"
      # }
      # |> bar()
      # """)

      # assert_style("""
      # [
      #   ~D[2016-01-01],
      #   ~D[2016-05-01]
      # ]
      # |> bar()
      # """)

      # assert_style("""
      # \"\"\"
      # Long
      # string
      # multiline
      # \"\"\"
      # |> bar()
      # """)

      assert_style("""
      ~s\"\"\"
      Long
      string
      multiline
      \"\"\"
      |> bar()
      """)
    end
  end

  describe "simple rewrites" do
    test "{Keyword/Map}.merge/2 of a single key => *.put/3" do
      for module <- ~w(Map Keyword) do
        assert_style("foo |> #{module}.merge(%{one_key: :bar}) |> bop()", "foo |> #{module}.put(:one_key, :bar) |> bop()")
      end
    end

    test "rewrites anon fun def ahd invoke to use then" do
      assert_style("a |> (& &1).()", "then(a, & &1)")
      assert_style("a |> (& {&1, &2}).(b)", "(&{&1, &2}).(a, b)")
      assert_style("a |> (& &1).() |> c", "a |> then(& &1) |> c()")

      assert_style("a |> (fn x, y -> {x, y} end).() |> c", "a |> then(fn x, y -> {x, y} end) |> c()")
      assert_style("a |> (fn x -> x end).()", "then(a, fn x -> x end)")
      assert_style("a |> (fn x -> x end).() |> c", "a |> then(fn x -> x end) |> c()")
    end

    test "rewrites then/2 when the passed function is a named function reference" do
      assert_style "a |> then(&fun/1) |> c", "a |> fun() |> c()"
      assert_style "a |> then(&DateTime.from_is8601/1) |> c", "a |> DateTime.from_is8601() |> c()"
      assert_style "a |> then(&DateTime.from_is8601/1)", "DateTime.from_is8601(a)"
      assert_style "a |> then(&fun(&1)) |> c", "a |> fun() |> c()"
      assert_style "a |> then(&fun(&1, d)) |> c", "a |> fun(d) |> c()"

      # Unary operators
      assert_style "a |> then(&(-&1)) |> c", "a |> Kernel.-() |> c()"
      assert_style "a |> then(&(+&1)) |> c", "a |> Kernel.+() |> c()"

      assert_style "a |> then(&fun(d, &1)) |> c()"
      assert_style "a |> then(&fun(&1, d, %{foo: &1})) |> c()"
    end

    test "adds parens to 1-arity pipes" do
      assert_style("a |> b |> c", "a |> b() |> c()")
    end

    test "reverse/concat" do
      assert_style("a |> Enum.reverse() |> Enum.concat()")
      assert_style("a |> Enum.reverse(bar) |> Enum.concat()")
      assert_style("a |> Enum.reverse(bar) |> Enum.concat(foo)")
      assert_style("a |> Enum.reverse() |> Enum.concat(foo)", "Enum.reverse(a, foo)")

      assert_style(
        """
        a
        |> Enum.reverse()
        |> Enum.concat([bar, baz])
        |> Enum.sum()
        """,
        """
        a
        |> Enum.reverse([bar, baz])
        |> Enum.sum()
        """
      )
    end

    test "filter/count" do
      for enum <- ~w(Enum Stream) do
        assert_style(
          """
          a
          |> #{enum}.filter(fun)
          |> Enum.count()
          |> IO.puts()
          """,
          """
          a
          |> Enum.count(fun)
          |> IO.puts()
          """
        )

        assert_style(
          """
          a
          |> #{enum}.filter(fun)
          |> Enum.count()
          """,
          """
          Enum.count(a, fun)
          """
        )

        assert_style(
          """
          if true do
            []
          else
            [a, b, c]
          end
          |> #{enum}.filter(fun)
          |> Enum.count()
          """,
          """
          if true do
            []
          else
            [a, b, c]
          end
          |> Enum.count(fun)
          """
        )
      end
    end

    test "map/join" do
      for enum <- ~w(Enum Stream) do
        assert_style("a|> #{enum}.map(b) |> Enum.join(x)", "Enum.map_join(a, x, b)")
      end
    end

    test "map/into" do
      for enum <- ~w(Enum Stream) do
        assert_style("a|> #{enum}.map(b)|> Enum.into(%{})", "Map.new(a, b)")
        assert_style("a |> #{enum}.map(b) |> Enum.into(unk)", "Enum.into(a, unk, b)")

        assert_style(
          "a |> #{enum}.map(b) |> Enum.into(%{some: :existing_map})",
          "Enum.into(a, %{some: :existing_map}, b)"
        )

        assert_style(
          """
          a_multiline_mapper
          |> #{enum}.map(fn %{gets: shrunk, down: to_a_more_reasonable} ->
            IO.puts "woo!"
            {shrunk, to_a_more_reasonable}
          end)
          |> Enum.into(size)
          """,
          """
          Enum.into(a_multiline_mapper, size, fn %{gets: shrunk, down: to_a_more_reasonable} ->
            IO.puts("woo!")
            {shrunk, to_a_more_reasonable}
          end)
          """
        )

        for collectable <- ~W(Map Keyword MapSet), new = "#{collectable}.new" do
          assert_style("a |> #{enum}.map(b) |> Enum.into(#{new}())", "#{new}(a, b)")

          # Regression: something about the meta wants newlines when it's in a def
          assert_style(
            """
            def foo() do
              filename_map = foo |> Enum.map(&{&1.filename, true}) |> Enum.into(%{})
            end
            """,
            """
            def foo do
              filename_map = Map.new(foo, &{&1.filename, true})
            end
            """
          )
        end
      end
    end

    test "map/new" do
      for collectable <- ~W(Map Keyword MapSet), new = "#{collectable}.new" do
        assert_style("a |> Enum.map(b) |> #{new}()", "#{new}(a, b)")
      end
    end

    test "into(%{})" do
      assert_style("a |> Enum.into(%{}) |> b()", "a |> Map.new() |> b()")
      assert_style("a |> Enum.into(%{}, mapper) |> b()", "a |> Map.new(mapper) |> b()")
    end

    test "into(Collectable.new())" do
      assert_style("a |> Enum.into(foo) |> b()")
      assert_style("a |> Enum.into(foo, mapper) |> b()")

      for collectable <- ~W(Map Keyword MapSet), new = "#{collectable}.new" do
        assert_style("a |> Enum.into(#{new}) |> b()", "a |> #{new}() |> b()")
        assert_style("a |> Enum.into(#{new}, mapper) |> b()", "a |> #{new}(mapper) |> b()")

        assert_style(
          """
          a
          |> Enum.map(b)
          |> Enum.into(#{new}, c)
          """,
          """
          a
          |> Enum.map(b)
          |> #{new}(c)
          """
        )
      end
    end
  end

  describe "configurable" do
    test "filename prefix is ignored" do
      assert_style("f(g(h(x))) |> j()", "f(g(h(x))) |> j()", "lib/test.exs",
        config: [
          {Styler.Style.Pipes, ignore_prefixes: ["lib/"]}
        ]
      )
    end

    test "filename not in prefix is styled" do
      assert_style("f(g(h(x))) |> j()", "x |> h() |> g() |> f() |> j()", "test/test.exs",
        config: [
          {Styler.Style.Pipes, ignore_prefixes: ["lib/"]}
        ]
      )
    end

    test "filename prefix is ignored with multiple prefixes" do
      assert_style("f(g(h(x))) |> j()", "f(g(h(x))) |> j()", "lib/test.exs",
        config: [
          {Styler.Style.Pipes, ignore_prefixes: ["lib/", "test/"]}
        ]
      )
    end

    test "if style is not present, no changes are made" do
      assert_style("f(g(h(x))) |> j()", "f(g(h(x))) |> j()", "lib/test.exs", config: [])
    end
  end
end
