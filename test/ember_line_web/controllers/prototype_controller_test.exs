defmodule EmberLineWeb.PrototypeControllerTest do
  @moduledoc "split-pages: the loaded prototype, served sandboxed to the board's hidden frame."
  use EmberLineWeb.ConnCase, async: false

  alias EmberLine.Modeling.PrototypeFile
  alias EmberLineWeb.PrototypeController

  setup do
    prototype_id = Ecto.UUID.generate()

    PrototypeFile.replace!(prototype_id, [
      %{name: "app.html", type: "text/html", content: "<html><body><p>App</p></body></html>"},
      %{name: "shot.png", type: "image/png", content: "png"}
    ])

    %{prototype_id: prototype_id}
  end

  test "serves the file with the crawler, sandboxed", %{conn: conn, prototype_id: id} do
    conn = get(conn, ~p"/prototype/#{PrototypeController.token(id, "app.html")}")

    assert html = response(conn, 200)
    assert html =~ ~r{<p>App</p><script>.*em-crawl.*</script></body></html>}s

    [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "sandbox allow-scripts;"
    refute policy =~ "allow-same-origin"
    assert policy =~ "connect-src 'none'"
    assert policy =~ "frame-ancestors 'self'"
  end

  test "a bad token, another file or a non-HTML file isn't served", %{
    conn: conn,
    prototype_id: id
  } do
    assert response(get(conn, ~p"/prototype/forged"), 404)
    assert response(get(conn, ~p"/prototype/#{PrototypeController.token(id, "other.html")}"), 404)
    assert response(get(conn, ~p"/prototype/#{PrototypeController.token(id, "shot.png")}"), 404)
  end
end
