defmodule EmberLineWeb.PrototypeController do
  @moduledoc """
  Serves a loaded prototype's HTML file to the board's hidden frame, so the
  browser can split it into pages (slice split-pages). The page crawler
  (`priv/prototype/bridge.js`) is added before `</body>`.

  The file is someone's own prototype, scripts and all, so it is served
  sandboxed: the `sandbox` policy gives it an opaque origin (no cookies, no
  access to Emberline's pages), it can't make requests or submit forms, and
  only Emberline may frame it. Access is by a short-lived signed token that
  BoardLive issues after checking the workspace and project. The headers
  are set in the router's `:prototype` pipeline.
  """
  use EmberLineWeb, :controller

  require Ash.Query

  alias EmberLine.Modeling.PrototypeFile

  @salt "prototype file"
  @max_age 3600

  @external_resource bridge_path = Path.join([__DIR__, "../../../priv/prototype/bridge.js"])
  @bridge "<script>" <> File.read!(bridge_path) <> "</script>"

  @doc "A token for one file of one prototype, for the board's frame."
  def token(prototype_id, name),
    do: Phoenix.Token.sign(EmberLineWeb.Endpoint, @salt, %{"p" => prototype_id, "n" => name})

  # The prototype's own HTML is the response, by design; see the moduledoc.
  # sobelow_skip ["XSS.SendResp"]
  def show(conn, %{"token" => token}) do
    with {:ok, %{"p" => prototype_id, "n" => name}} <-
           Phoenix.Token.verify(EmberLineWeb.Endpoint, @salt, token, max_age: @max_age),
         %PrototypeFile{type: "text/html", content: html} <- find(prototype_id, name) do
      # The sandbox policy and other headers come from the router's :prototype pipeline.
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, with_bridge(html))
    else
      _expired_or_missing -> send_resp(conn, 404, "")
    end
  end

  defp find(prototype_id, name) do
    PrototypeFile
    |> Ash.Query.filter(prototype_id == ^prototype_id and name == ^name)
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
