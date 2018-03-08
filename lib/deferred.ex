defprotocol DeferredValue do
  @moduledoc """
  Documentation for Deferred.
  """
  @spec evaluate(t) :: t
  def evaluate(deferred_value)

  @spec evaluate_once(t) :: t
  def evaluate_once(deferred_value)

  @spec get_value(t) :: any | nil
  def get_value(deferred_value)

  @spec add_then(t, callback: (any -> any)) :: t
  def add_then(deferred_value, callback)
end

defmodule Deferred do
  defp get_await(expression, deep \\ false)
  defp get_await(expr = {:await, _ctx, _args}, _), do: expr

  defp get_await({:__block__, _, _}, false) do
    nil
  end

  defp get_await({_fun, _ctx, args}, deep) when is_list(args), do: get_await(args, deep)

  defp get_await({:do, block}, deep) do
    get_await(block, deep)
  end

  defp get_await([], _), do: nil
  defp get_await([arg | args], deep), do: get_await(arg, deep) || get_await(args, deep)

  defp get_await(_expr, _) do
    nil
  end

  defp replace_expression(await, await, replacement), do: replacement

  defp replace_expression({fun, ctx, args}, await, replacement),
    do: {fun, ctx, replace_expression(args, await, replacement)}

  defp replace_expression({:do, block}, await, replacement),
    do: {:do, replace_expression(block, await, replacement)}

  defp replace_expression([arg | args], await, replacement),
    do: [
      replace_expression(arg, await, replacement) | replace_expression(args, await, replacement)
    ]

  defp replace_expression(other, _, _), do: other

  defp md5_hash(binary) do
    :crypto.hash(:md5, binary)
  end

  defp fun_to_hash(fun) do
    fun
    |> :erlang.term_to_binary()
    |> md5_hash
    |> Base.encode16()
    |> String.downcase()
    |> String.slice(0, 5)
  end

  defp expression_to_var_name(expr) do
    :"deferred_#{fun_to_hash(expr)}"
  end

  defp wrap(expr, lines, await) do
    {:await, _, [deferred_val]} = await

    var = Macro.var(expression_to_var_name(await), nil)

    lines =
      [expr | lines]
      |> replace_expression(await, var)
      |> rewrite_lines()

    quote do
      then(unquote(deferred_val), fn unquote(var) ->
        (unquote_splicing(lines))
      end)
    end
  end

  defp wrap_deep({:=, ctx, [assignment, expr]}, lines, _) do
    expr = rewrite(expr)

    var = Macro.var(expression_to_var_name(expr), nil)

    lines =
      [{:=, ctx, [assignment, var]} | lines]
      |> rewrite_lines()

    quote do
      then(unquote(expr), fn unquote(var) ->
        (unquote_splicing(lines))
      end)
    end
  end

  defp wrap_deep(expr, lines, _) do
    expr = rewrite(expr)

    var = Macro.var(expression_to_var_name(expr), nil)

    lines =
      [var | lines]
      |> rewrite_lines()

    quote do
      then(unquote(expr), fn unquote(var) ->
        (unquote_splicing(lines))
      end)
    end
  end

  defp rewrite_lines([]), do: []

  defp rewrite_lines([line | lines]) do
    await_deep = get_await(line, true)
    await_shallow = get_await(line)

    if await_deep do
      if await_shallow do
        [wrap(line, lines, await_shallow)]
      else
        [wrap_deep(line, lines, await_deep)]
      end
    else
      [rewrite(line) | rewrite_lines(lines)]
    end
  end

  defp rewrite({:__block__, ctx, lines}) do
    {:__block__, ctx, rewrite_lines(lines)}
  end

  defp rewrite([{:do, block}]), do: [{:do, rewrite(block)}]

  defp rewrite({:await, _, [fun]}) do
    # just remove the keyword
    fun
  end

  defp rewrite(_expression = {form, ctx, args}) when is_list(args) do
    {form, ctx, rewrite_args(args)}
  end

  defp rewrite({form, ctx, args}), do: {form, ctx, args}

  defp rewrite(exp) do
    exp
  end

  defp rewrite_args([]), do: []

  defp rewrite_args([arg | args]) do
    [rewrite(arg) | rewrite_args(args)]
  end

  def rewrite_fun(
        {:def, fun_ctx, [fun_name]},
        do: expr = {_, _, _}
      ) do
    {:def, fun_ctx, [fun_name, [do: rewrite(expr)]]}
  end

  defmacro deferred(
             definition,
             do_block
           ) do
    rewrite_fun(definition, do_block)
  end

  def then(nil, func), do: func

  def then(deferred_value, func) do
    DeferredValue.add_then(
      deferred_value,
      func
    )
  end

  def evaluate(deferred_value), do: DeferredValue.evaluate(deferred_value)
  def get_value(deferred_value), do: DeferredValue.get_value(deferred_value)
end