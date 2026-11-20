defmodule EmberLine.Modeling.Derive.Claude do
  @moduledoc """
  The Claude call for derive-model: one Messages API request, made on the
  server with the key in the ANTHROPIC_API_KEY setting (never a person's
  own), through Req. The model is claude-sonnet-5-5 unless the
  EMBERLINE_DERIVE_MODEL setting names another.

  The request streams, so a long outline can't run into an HTTP timeout,
  and the text is read once the stream ends. Refusals go to Anthropic's
  default fallback model (server-side fallbacks).

  Errors are the model's two: `:claude_unreachable` (rate limited, timed
  out, a 5xx, or any other failure to get an answer) and
  `:answer_unreadable` (a refusal, or an answer cut off at max_tokens).
  """

  require Logger

  @url "https://api.anthropic.com/v1/messages"
  @api_version "2026-10-21"
  @fallback_beta "server-side-fallback-2026-07-01"
  @default_model "claude-sonnet-5-5"
  # Streaming, so the output can be long without an HTTP timeout.
  @max_tokens 64_000

  @type image :: %{media_type: String.t(), data: binary()}

  @doc "Sends the images, then the prompt, and returns Claude's text."
  @spec ask(String.t(), [image()]) ::
          {:ok, String.t()} | {:error, :claude_unreachable | :answer_unreadable}
  def ask(prompt, images \\ []) do
    case config()[:api_key] do
      key when key in [nil, ""] ->
        Logger.error("derive-model: ANTHROPIC_API_KEY isn't set")
        {:error, :claude_unreachable}

      key ->
        key |> request(prompt, images) |> answer()
    end
  end

  defp request(key, prompt, images) do
    content =
      Enum.map(images, fn image ->
        %{
          type: "image",
          source: %{type: "base64", media_type: image.media_type, data: Base.encode64(image.data)}
        }
      end) ++ [%{type: "text", text: prompt}]

    body = %{
      model: config()[:model] || @default_model,
      max_tokens: @max_tokens,
      stream: true,
      output_config: %{effort: "high"},
      fallbacks: "default",
      messages: [%{role: "user", content: content}]
    }

    [
      url: @url,
      json: body,
      headers: [
        {"x-api-key", key},
        {"anthropic-version", @api_version},
        {"anthropic-beta", @fallback_beta}
      ],
      into: "",
      # Retry 429, 5xx and timeouts twice, honouring retry-after.
      retry: :transient,
      max_retries: 2,
      # Between streamed chunks; the API sends pings while Claude thinks.
      receive_timeout: 300_000
    ]
    |> Keyword.merge(config()[:req_options] || [])
    |> Req.post()
  end

  defp answer({:ok, %Req.Response{status: 200, body: body}}), do: read_stream(body)

  defp answer({:ok, %Req.Response{status: status, body: body}}) do
    Logger.warning("derive-model: Claude answered #{status}: #{inspect(body, limit: 20)}")
    {:error, :claude_unreachable}
  end

  defp answer({:error, exception}) do
    Logger.warning("derive-model: Claude couldn't be reached: #{inspect(exception)}")
    {:error, :claude_unreachable}
  end

  # The server-sent events: text deltas make up the answer; the stop reason
  # says whether it's whole. An error event mid-stream (overloaded) counts
  # as unreachable.
  defp read_stream(body) do
    events =
      body
      |> String.split(~r/\r?\n\r?\n/, trim: true)
      |> Enum.flat_map(&event_data/1)

    stop_reason =
      Enum.find_value(events, fn
        %{"type" => "message_delta", "delta" => %{"stop_reason" => reason}} -> reason
        _other -> nil
      end)

    text =
      for %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => t}} <-
            events,
          into: "",
          do: t

    cond do
      Enum.any?(events, &match?(%{"type" => "error"}, &1)) -> {:error, :claude_unreachable}
      stop_reason in ["refusal", "max_tokens"] -> {:error, :answer_unreadable}
      true -> {:ok, text}
    end
  end

  defp event_data(block) do
    block
    |> String.split(~r/\r?\n/)
    |> Enum.flat_map(fn
      "data: " <> json ->
        case Jason.decode(json) do
          {:ok, data} -> [data]
          {:error, _} -> []
        end

      _other ->
        []
    end)
  end

  defp config, do: Application.get_env(:ember_line, __MODULE__, [])
end
