defmodule Membrane.Element.Base.Mixin.CommonBehaviour do
  @moduledoc """
  Module defining behaviour common to all elements.

  When used declares behaviour implementation, provides default callback definitions
  and imports macros.

  For more information on implementing elements, see `Membrane.Element.Base`.
  """
  alias Membrane.{Action, Core, Element, Event, Time}
  alias Core.CallbackHandler
  alias Element.{Action, CallbackContext, Pad}

  use Bunch

  @typedoc """
  Type that defines all valid return values from most callbacks.
  """
  @type callback_return_t :: CallbackHandler.callback_return_t(Action.t(), Element.state_t())

  @doc """
  Automatically implemented callback returning specification of pads exported
  by the element.

  Generated by `Membrane.Element.Base.Mixin.SinkBehaviour.def_input_pads/1`
  and `Membrane.Element.Base.Mixin.SourceBehaviour.def_output_pads/1` macro.
  """
  @callback membrane_pads() :: [{Pad.name_t(), Element.Pad.description_t()}]

  @doc """
  Automatically implemented callback used to determine if module is a membrane element.
  """
  @callback membrane_element? :: true

  @doc """
  Automatically implemented callback determining whether element is a source,
  a filter or a sink.
  """
  @callback membrane_element_type :: Element.type_t()

  @doc """
  Callback invoked on initialization of element process. It should parse options
  and initialize element internal state. Internally it is invoked inside
  `c:GenServer.init/1` callback.
  """
  @callback handle_init(options :: Element.options_t()) ::
              {:ok, Element.state_t()}
              | {:error, any}

  @doc """
  Callback invoked when element goes to `:prepared` state from state `:stopped` and should get
  ready to enter `:playing` state.

  Usually most resources used by the element are allocated here.
  For example, if element opens a file, this is the place to try to actually open it
  and return error if that has failed. Such resources should be released in `c:handle_prepared_to_stopped/1`.
  """
  @callback handle_stopped_to_prepared(
              context :: CallbackContext.PlaybackChange.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when element goes to `:prepared` state from state `:playing` and should get
  ready to enter `:stopped` state.

  All resources allocated in `c:handle_prepared_to_playing/2` callback should be released here, and no more buffers or
  demands should be sent.
  """
  @callback handle_playing_to_prepared(
              context :: CallbackContext.PlaybackChange.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when element is supposed to start playing (goes from state `:prepared` to `:playing`).

  This is moment when initial demands are sent and first buffers are generated
  if there are any pads in the push mode.
  """
  @callback handle_prepared_to_playing(
              context :: CallbackContext.PlaybackChange.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when element is supposed to stop (goes from state `:prepared` to `:stopped`).

  Usually this is the place for releasing all remaining resources
  used by the element. For example, if element opens a file in `c:handle_stopped_to_prepared/2`,
  this is the place to close it.
  """
  @callback handle_prepared_to_stopped(
              context :: CallbackContext.PlaybackChange.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when element receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving ticks from timer, data sent from NIFs or other stuff.
  """
  @callback handle_other(
              message :: any(),
              context :: CallbackContext.Other.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback that is called when new pad has beed added to element. Executed
  ONLY for dynamic pads.
  """
  @callback handle_pad_added(
              pad :: Pad.ref_t(),
              context :: CallbackContext.PadAdded.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback that is called when some pad of the element has beed removed. Executed
  ONLY for dynamic pads.
  """
  @callback handle_pad_removed(
              pad :: Pad.ref_t(),
              context :: CallbackContext.PadRemoved.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback that is called when event arrives.

  Events may arrive from both sinks and sources. In filters by default event is
  forwarded to all sources or sinks, respectively. If event is either
  `Membrane.Event.StartOfStream` or `Membrane.Event.EndOfStream`, notification
  is sent, to notify the pipeline that data processing is started or finished.
  This behaviour can be overriden, e.g. by sending end of stream notification
  after elements internal buffers become empty.
  """
  @callback handle_event(
              pad :: Pad.ref_t(),
              event :: Event.t(),
              context :: CallbackContext.Event.t(),
              state :: Element.state_t()
            ) :: callback_return_t

  @doc """
  Callback invoked when element is shutting down just before process is exiting.
  Internally called in `c:GenServer.termintate/2` callback.
  """
  @callback handle_shutdown(state :: Element.state_t()) :: :ok

  @default_types_params %{
    atom: [spec: quote_expr(atom)],
    boolean: [spec: quote_expr(boolean)],
    string: [spec: quote_expr(String.t())],
    keyword: [spec: quote_expr(keyword)],
    struct: [spec: quote_expr(struct)],
    caps: [spec: quote_expr(struct)],
    time: [spec: quote_expr(Time.t()), inspector: &Time.to_code_str/1]
  }

  @doc """
  Macro that defines options that parametrize element.

  It automatically generates appropriate struct.

  `def_options/1` should receive keyword list, where each key is option name and
  is described by another keyword list with following fields:

    * `type:` atom, used for parsing
    * `spec:` typespec for value in struct. If ommitted, for types:
      `#{inspect(Map.keys(@default_types_params))}` the default typespec is provided.
      For others typespec is set to `t:any/0`
    * `default:` default value for option. If not present, value for this option
      will have to be provided each time options struct is created
    * `inspector:` function converting fields' value to a string. Used when
      creating documentation instead of `inspect/1`
    * `description:` string describing an option. It will be present in value returned by `options/0`
      and in typedoc for the struct.
  """
  defmacro def_options(options) do
    {opt_specs, escaped_opts} = extract_specs(options)
    opt_typespec_ast = {:%{}, [], Keyword.put(opt_specs, :__struct__, __CALLER__.module)}
    # opt_typespec_ast is equivalent of typespec %__CALLER__.module{key: value, ...}
    typedoc =
      escaped_opts
      |> Enum.map(fn {k, v} ->
        desc = v |> Keyword.get(:description, "")

        default_val_desc =
          if Keyword.has_key?(v, :default) do
            inspector =
              v
              |> Keyword.get(
                :inspector,
                @default_types_params[v[:type]][:inspector] || quote(do: &inspect/1)
              )

            quote do
              "Defaults to `#{unquote(inspector).(unquote(v)[:default])}`"
            end
          else
            ""
          end

        format_option_docs(
          quote do
            """
            `#{Atom.to_string(unquote(k))}` - \
            #{String.trim(unquote(desc))}

            #{unquote(default_val_desc)}
            """
          end
        )
      end)
      |> Enum.reduce(fn x, acc ->
        quote do
          unquote(x) <> "\n" <> unquote(acc)
        end
      end)

    quote do
      @typedoc """
      Struct containing options for `#{inspect(__MODULE__)}`

      #{unquote(typedoc)}
      """
      @type t :: unquote(opt_typespec_ast)

      @doc """
      Returns description of options available for this module
      """
      @spec options() :: keyword
      def options(), do: unquote(escaped_opts)

      @enforce_keys unquote(escaped_opts)
                    |> Enum.reject(fn {k, v} -> v |> Keyword.has_key?(:default) end)
                    |> Keyword.keys()

      defstruct unquote(escaped_opts)
                |> Enum.map(fn {k, v} -> {k, v[:default]} end)
    end
  end

  defp format_option_docs(docs) do
    quote do
      unquote(docs)
      |> String.trim()
      |> String.replace("\n\n", "\n\n  ")
      |> String.replace_prefix("", "* ")
    end
  end

  defp extract_specs(kw) when is_list(kw) do
    with_default_specs =
      kw
      |> Enum.map(fn {k, v} ->
        default_val = @default_types_params[v[:type]][:spec] || quote_expr(any)

        {k, v |> Keyword.put_new(:spec, default_val)}
      end)

    opt_typespecs =
      with_default_specs
      |> Enum.map(fn {k, v} -> {k, v[:spec]} end)

    escaped_opts =
      with_default_specs
      |> Enum.map(fn {k, v} ->
        {k, v |> Keyword.update!(:spec, &Macro.to_string/1)}
      end)

    {opt_typespecs, escaped_opts}
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      use Membrane.Log, tags: :element, import: false

      alias Membrane.Element.CallbackContext, as: Ctx

      import unquote(__MODULE__), only: [def_options: 1]

      @impl true
      def membrane_element?, do: true

      @impl true
      def handle_init(%opt_struct{} = options), do: {:ok, options |> Map.from_struct()}
      def handle_init(options), do: {:ok, options}

      @impl true
      def handle_stopped_to_prepared(_context, state), do: {:ok, state}

      @impl true
      def handle_playing_to_prepared(_context, state), do: {:ok, state}

      @impl true
      def handle_prepared_to_playing(_context, state), do: {:ok, state}

      @impl true
      def handle_prepared_to_stopped(_context, state), do: {:ok, state}

      @impl true
      def handle_other(_message, _context, state), do: {:ok, state}

      @impl true
      def handle_pad_added(_pad, _context, state), do: {:ok, state}

      @impl true
      def handle_pad_removed(_pad, _context, state), do: {:ok, state}

      @impl true
      def handle_event(pad, %Event.StartOfStream{}, _context, state),
        do: {{:ok, notify: {:start_of_stream, pad}}, state}

      @impl true
      def handle_event(pad, %Event.EndOfStream{}, _context, state),
        do: {{:ok, notify: {:end_of_stream, pad}}, state}

      def handle_event(_pad, _event, _context, state), do: {:ok, state}

      @impl true
      def handle_shutdown(_state), do: :ok

      defoverridable handle_init: 1,
                     handle_stopped_to_prepared: 2,
                     handle_playing_to_prepared: 2,
                     handle_prepared_to_playing: 2,
                     handle_prepared_to_stopped: 2,
                     handle_other: 3,
                     handle_pad_added: 3,
                     handle_pad_removed: 3,
                     handle_event: 4,
                     handle_shutdown: 1
    end
  end
end