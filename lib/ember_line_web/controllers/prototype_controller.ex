defmodule EmberLineWeb.PrototypeController do
  @moduledoc """
  Serves a loaded prototype's files and a split's pages: to the board's
  hidden frame, so the browser can split it into pages (slice split-pages),
  and to the board's tabs (slice view-intake). The page crawler
  (`priv/prototype/bridge.js`) is added before an HTML file's `</body>`.

  The files are someone's own prototype, scripts and all, so they are served
  sandboxed: the `sandbox` policy gives them an opaque origin (no cookies, no
  access to Emberline's pages), they can't make requests or submit forms, and
  only Emberline may frame them. The board's frames add their own `sandbox`
  attribute, which turns scripts off for static HTML and pages. Access is by
  a short-lived signed token that BoardLive issues after checking the
  workspace and project. The headers are set in the router's `:prototype`
  pipeline.
  """
  use EmberLineWeb, :controller

  require Ash.Query

  alias EmberLine.Modeling.{PrototypeFile, PrototypePage}

  @salt "prototype file"
  @max_age 3600

  @external_resource bridge_path = Path.join([__DIR__, "../../../priv/prototype/bridge.js"])
  @bridge "<script>" <> File.read!(bridge_path) <> "</script>"

  @doc "A token for one file of one prototype."
  def token(prototype_id, name),
    do: Phoenix.Token.sign(EmberLineWeb.Endpoint, @salt, %{"p" => prototype_id, "n" => name})

  @doc "A token for one page of a split prototype, by its position."
  def page_token(prototype_id, position),
    do: Phoenix.Token.sign(EmberLineWeb.Endpoint, @salt, %{"p" => prototype_id, "g" => position})

  def show(conn, %{"token" => token}) do
    case Phoenix.Token.verify(EmberLineWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, payload} -> serve(conn, find(payload))
      {:error, _expired_or_forged} -> send_resp(conn, 404, "")
    end
  end

  # The prototype's own files are the response, by design; see the moduledoc.
  # The type is one of PrototypeFile's (HTML or a screenshot). The sandbox
  # policy and other headers come from the router's :prototype pipeline.
  # sobelow_skip ["XSS.SendResp", "XSS.ContentType"]
  defp serve(conn, found) do
    case found do
      %PrototypeFile{type: "text/html", content: html} ->
        conn |> put_resp_content_type("text/html") |> send_resp(200, with_bridge(html))

      %PrototypeFile{type: type, content: content} ->
        conn |> put_resp_content_type(type, nil) |> send_resp(200, content)

      %PrototypePage{html: html} ->
        conn |> put_resp_content_type("text/html") |> send_resp(200, html)

      nil ->
        send_resp(conn, 404, "")
    end
  end

  defp find(%{"p" => prototype_id, "n" => name}) do
    PrototypeFile
    |> Ash.Query.filter(prototype_id == ^prototype_id and name == ^name)
    |> Ash.read_one!(authorize?: false)
  end

  defp find(%{"p" => prototype_id, "g" => position}) do
    PrototypePage
    |> Ash.Query.filter(prototype_id == ^prototype_id and position == ^position)
    |> Ash.read_one!(authorize?: false)
  end

  # Before the last </body>, or at the end when there is none.
  defp with_bridge(html) do
    case :binary.matches(html, ["</body>", "</BODY>"]) do
      [] ->
        html <> @bridge

      matches ->
        {at, _len} = List.last(matches)
        binary_part(html, 0, at) <> @bridge <> binary_part(html, at, byte_size(html) - at)
    end
  end
end
