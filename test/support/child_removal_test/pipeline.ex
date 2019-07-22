defmodule Membrane.Support.ChildRemovalTest.Pipeline do
  @moduledoc false
  use Membrane.Pipeline

  @impl true
  def handle_init(opts) do
    children =
      [
        source: opts.source,
        filter1: opts.filter1,
        filter2: opts.filter2,
        sink: opts.sink
      ]
      |> maybe_add_extra_source(opts)

    links =
      %{
        {:source, :output} => {:filter1, :input, buffer: [preferred_size: 10]},
        {:filter1, :output} => {:filter2, :input, buffer: [preferred_size: 10]},
        {:filter2, :output} => {:sink, :input, buffer: [preferred_size: 10]}
      }
      |> maybe_add_extra_source_link(opts)

    spec = %Pipeline.Spec{
      children: children,
      links: links
    }

    {{:ok, spec}, %{target: opts.target}}
  end

  @impl true
  def handle_other({:child_msg, name, msg}, state) do
    {{:ok, forward: {name, msg}}, state}
  end

  def handle_other({:remove_child, name}, state) do
    {{:ok, remove_child: name}, state}
  end

  @impl true
  def handle_prepared_to_playing(%{target: target} = state) do
    send(target, :playing)
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_stopped(%{target: t} = state) do
    send(t, :pipeline_stopped)
    {:ok, state}
  end

  defp maybe_add_extra_source(children, %{extra_source: source}) do
    Keyword.update(
      children,
      :filter2,
      nil,
      fn f -> %{f | two_input_pads: true} end
    ) ++
      [extra_source: source]
  end

  defp maybe_add_extra_source(children, _) do
    children
  end

  defp maybe_add_extra_source_link(links, %{extra_source: _}) do
    Map.put(links, {:extra_source, :output}, {:filter2, :input2, buffer: [preferred_size: 10]})
  end

  defp maybe_add_extra_source_link(links, _) do
    links
  end
end
