defmodule DeferredTest do
  use ExUnit.Case
  doctest Deferred
  import Defer
  alias Defer.ExampleDeferredValue

  defp do_rewrite(fun_ast) do
    {:def, def_ctx, [fun_name, [{:do, do_block}]]} = fun_ast
    rewrite_fun({:def, def_ctx, [fun_name]}, [{:do, do_block}])
  end

  def ast_to_string(ast) do
    "#{ast |> Macro.to_string() |> Code.format_string!()}"
  end

  defp assert_output(input, expected_output) do
    if ast_to_string(do_rewrite(input)) != ast_to_string(expected_output) do
      IO.puts("\n\nAssertion error:")
      IO.puts("\n\nInput:\n\n")
      IO.puts(ast_to_string(input))
      IO.puts("\n\nExpected:\n\n")
      IO.puts(ast_to_string(expected_output))
      # IO.inspect(expected_output)
      IO.puts("\n\nInstead got:\n\n")
      IO.puts(ast_to_string(do_rewrite(input)))
      # IO.inspect(do_rewrite(input))
    end

    assert ast_to_string(expected_output) == ast_to_string(do_rewrite(input))
  end

  test "then macro" do
    first_callback = fn _ ->
      1
    end

    second_callback = fn val ->
      val + 2
    end

    then_val =
      then(
        %ExampleDeferredValue{
          callback: first_callback
        },
        second_callback
      )

    assert %ExampleDeferredValue{} = then_val
  end

  deferred def test do
    val_1 = await(%ExampleDeferredValue{callback: fn _ -> 10 end})
    val_2 = await(%ExampleDeferredValue{callback: fn _ -> 20 end})

    val_1 + val_2
  end

  test "defer macro" do
    assert %ExampleDeferredValue{evaluated?: false} = test()
    assert evaluate(test()) == 30
  end

  test "test correct evaluation" do
    deferred_value =
      then(
        %ExampleDeferredValue{
          callback: fn _ ->
            1
          end
        },
        fn deferred_1__ ->
          val1 = deferred_1__

          then(
            %ExampleDeferredValue{
              callback: fn _ ->
                2
              end
            },
            fn deferred_2__ ->
              val2 = deferred_2__

              val1 + val2
            end
          )
        end
      )

    assert evaluate(deferred_value) == 3
  end

  # test "a case statement" do
  #   input =
  #     quote do
  #       def test(input) do
  #         test = 1

  #         test2 =
  #           case test do
  #             input = 1 -> await(%ExampleDeferredValue{callback: fn -> input + 2 end})
  #             input -> 100
  #           end

  #         test + test2
  #       end
  #     end

  #   expected_output =
  #     quote do
  #       def test(input) do
  #         test = 1

  #         then(
  #           case test do
  #             input = 1 -> %ExampleDeferredValue{callback: fn -> input + 2 end}
  #             input -> 100
  #           end,
  #           fn deferred_1__ ->
  #             test2 = deferred_1__

  #             test + test2
  #           end
  #         )
  #       end
  #     end

  #   assert assert_output(input, expected_output)
  # end

  test "await in a nested block" do
    input =
      quote do
        def test(input) do
          test = 1

          bla =
            if input == 3 do
              test2 = await(%ExampleDeferredValue{callback: fn _ -> input + 4 end})
              test2 + test
            end

          bla + test
        end
      end

    expected_output =
      quote do
        def test(input) do
          test = 1

          then(
            if input == 3 do
              then(%ExampleDeferredValue{callback: fn _ -> input + 4 end}, fn deferred_abe29 ->
                test2 = deferred_abe29
                test2 + test
              end)
            end,
            fn deferred_1dbe6 ->
              bla = deferred_1dbe6
              bla + test
            end
          )
        end
      end

    assert assert_output(input, expected_output)
  end

  test "two awaits in function call" do
    input =
      quote do
        def test(input) do
          bla = compare(await(@test_value1), await(@test_value2))
          IO.inspect(bla)
        end
      end

    expected_output =
      quote do
        def test(input) do
          then(@test_value1, fn deferred_c5495 ->
            then(@test_value2, fn deferred_7d1aa ->
              bla = compare(deferred_c5495, deferred_7d1aa)
              IO.inspect(bla)
            end)
          end)
        end
      end

    assert assert_output(input, expected_output)
  end

  test "multiple awaits" do
    input =
      quote do
        def test do
          val_1 = await(@test_value1)
          val_2 = await(@test_value2)

          val_1 + val_2
        end
      end

    expected_output =
      quote do
        def test do
          then(@test_value1, fn deferred_c5495 ->
            val_1 = deferred_c5495

            then(@test_value2, fn deferred_7d1aa ->
              val_2 = deferred_7d1aa
              val_1 + val_2
            end)
          end)
        end
      end

    assert assert_output(input, expected_output)
  end

  test "one value" do
    input =
      quote do
        def test do
          await(%ExampleDeferredValue{
            callback: fn _ ->
              5
            end
          })
        end
      end

    expected_output =
      quote do
        def test do
          %ExampleDeferredValue{
            callback: fn _ ->
              5
            end
          }
        end
      end

    assert assert_output(input, expected_output)
  end

  test "nested invocations of deferred functions" do
    input =
      quote do
        def test do
          val_1 = await(nested_1())

          val_2 = await(@test_value2)

          val_1 + val_2
        end
      end

    expected_output =
      quote do
        def test do
          then(nested_1(), fn deferred_5a695 ->
            val_1 = deferred_5a695

            then(@test_value2, fn deferred_7d1aa ->
              val_2 = deferred_7d1aa
              val_1 + val_2
            end)
          end)
        end
      end

    assert assert_output(input, expected_output)
  end
end