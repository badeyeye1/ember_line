defmodule EmberLineWeb.PrototypeControllerTest do
  @moduledoc """
  The loaded prototype, served sandboxed: to the board's hidden frame
  (split-pages) and its tabs (view-intake).
  """
  use EmberLineWeb.ConnCase, async: false

  alias EmberLine.Modeling.{PrototypeFile, PrototypePage}
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

  test "serves a screenshot as its image type", %{conn: conn, prototype_id: id} do
    conn = get(conn, ~p"/prototype/#{PrototypeController.token(id, "shot.png")}")

    assert response(conn, 200) == "png"
    assert response_content_type(conn, :png) =~ "image/png"
  end

  test "serves a split page's HTML, sandboxed", %{conn: conn, prototype_id: id} do
    :ok =
      PrototypePage.replace!(id, [
        %{title: "Home", role: "Host", route: "#home", html: "<p>Home</p>"},
        %{title: "Workshops", role: "Host", route: "#ws", html: "<p>Workshops</p>"}
      ])

    conn = get(conn, ~p"/prototype/#{PrototypeController.page_token(id, 2)}")

    assert response(conn, 200) == "<p>Workshops</p>"
    assert [_policy] = get_resp_header(conn, "content-security-policy")
  end

  test "a bad token or another file or page isn't served", %{conn: conn, prototype_id: id} do
    assert response(get(conn, ~p"/prototype/forged"), 404)
    assert response(get(conn, ~p"/prototype/#{PrototypeController.token(id, "other.html")}"), 404)
    assert response(get(conn, ~p"/prototype/#{PrototypeController.page_token(id, 1)}"), 404)
  end
end
