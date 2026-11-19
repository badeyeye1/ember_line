defmodule EmberLineWeb.UITest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EmberLineWeb.UI

  describe "avatar" do
    test "shows initials and a token colour class, with no inline style (CSP)" do
      html = render_component(&UI.avatar/1, name: "Ada Lovelace", color: "#e07a5f")

      assert html =~ "AL"
      assert html =~ ~r/class="ui-av tone-[0-7]"/
      refute html =~ "style="
    end

    test "the same colour always gets the same tone" do
      assert UI.avatar_tone("#e07a5f") == UI.avatar_tone("#e07a5f")
    end
  end
end
