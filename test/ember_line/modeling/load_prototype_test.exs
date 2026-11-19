defmodule EmberLine.Modeling.LoadPrototypeTest do
  @moduledoc "Slice load-prototype: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false
  use EmberLine.EventModelCase

  alias Commanded.Serialization.JsonDecoder
  alias EmberLine.Modeling.{Errors, Intake, PrototypeFile}
  alias EmberLine.Modeling.Project

  alias EmberLine.Modeling.Project.{
    LoadPrototype,
    ProjectCreated,
    ProjectDeleted,
    PrototypeLoaded
  }

  @at ~U[2026-11-19 10:00:00Z]

  setup do
    %{
      pr: Ecto.UUID.generate(),
      p1: Ecto.UUID.generate(),
      p9: Ecto.UUID.generate(),
      u1: Ecto.UUID.generate()
    }
  end

  defp created(ctx),
    do: %ProjectCreated{project_id: ctx.pr, name: "Emberline", workspace_id: Ecto.UUID.generate()}

  defp load(ctx, fields) do
    struct!(
      LoadPrototype,
      Map.merge(
        %{
          prototype_id: ctx.p1,
          project_id: ctx.pr,
          source: :files,
          file_names: [],
          unreadable_file_names: [],
          ignored_file_names: [],
          interactive: false,
          too_large_file_names: [],
          total_bytes: 0,
          loaded_by: ctx.u1,
          loaded_at: @at
        },
        Map.new(fields)
      )
    )
  end

  defp loaded(ctx, fields) do
    struct!(
      PrototypeLoaded,
      Map.merge(
        %{
          prototype_id: ctx.p1,
          project_id: ctx.pr,
          source: :files,
          file_names: [],
          file_count: 0,
          skipped_count: 0,
          ignored_file_names: [],
          interactive: false,
          loaded_by: ctx.u1,
          loaded_at: @at
        },
        Map.new(fields)
      )
    )
  end

  defp pages(range),
    do: Enum.map(range, &"page-#{String.pad_leading(to_string(&1), 2, "0")}.html")

  defp rejects(_ctx, given, command, message) do
    assert {:error, reason} =
             Project.execute(Enum.reduce(given, %Project{}, &Project.apply(&2, &1)), command)

    assert Errors.message(reason) == message
  end

  # --- the decision ---------------------------------------------------------

  test "Load several HTML files", ctx do
    assert_decides(
      Project,
      [created(ctx)],
      load(ctx, file_names: ["a.html", "b.html"], total_bytes: 70_000),
      [loaded(ctx, file_names: ["a.html", "b.html"], file_count: 2)]
    )
  end

  test "Paste the HTML of an interactive prototype", ctx do
    assert_decides(
      Project,
      [created(ctx)],
      load(ctx,
        source: :paste,
        file_names: ["pasted-prototype.html"],
        interactive: true,
        total_bytes: 900_000
      ),
      [
        loaded(ctx,
          source: :paste,
          file_names: ["pasted-prototype.html"],
          file_count: 1,
          interactive: true
        )
      ]
    )
  end

  test "Usable files mixed with others", ctx do
    assert_decides(
      Project,
      [created(ctx)],
      load(ctx,
        file_names: ["home.html", "home.png"],
        ignored_file_names: ["notes.txt", "logo.svg"],
        total_bytes: 400_000
      ),
      [
        loaded(ctx,
          file_names: ["home.html", "home.png"],
          file_count: 2,
          ignored_file_names: ["notes.txt", "logo.svg"]
        )
      ]
    )

    assert Intake.ignored_note(["notes.txt", "logo.svg"]) ==
             "Ignored notes.txt and logo.svg: only HTML, screenshots and .zip files are used."
  end

  test "No usable screens", ctx do
    rejects(
      ctx,
      [created(ctx)],
      load(ctx, ignored_file_names: ["notes.txt"], total_bytes: 2000),
      "We couldn't find any screens in those files. Drop HTML files, screenshots or a .zip of the prototype."
    )
  end

  test "Files unreadable", ctx do
    rejects(
      ctx,
      [created(ctx)],
      load(ctx, unreadable_file_names: ["broken.zip"], total_bytes: 5000),
      "We couldn't read broken.zip. Check the file and try again."
    )
  end

  test "A file is too large", ctx do
    rejects(
      ctx,
      [created(ctx)],
      load(ctx,
        file_names: ["video-walkthrough.html"],
        too_large_file_names: ["video-walkthrough.html"],
        total_bytes: 26_000_000
      ),
      "video-walkthrough.html is larger than 20 MB. Remove embedded videos or large images and try again."
    )
  end

  test "Too much in one load", ctx do
    rejects(
      ctx,
      [created(ctx)],
      load(ctx, file_names: pages(1..60), total_bytes: 120_000_000),
      "These files add up to more than 100 MB. Load fewer at a time, or remove large images."
    )
  end

  test "More files than the limit", ctx do
    assert_decides(
      Project,
      [created(ctx)],
      load(ctx, file_names: Enum.shuffle(pages(1..95)), total_bytes: 3_000_000),
      [loaded(ctx, file_names: pages(1..80), file_count: 80, skipped_count: 15)]
    )

    assert Intake.skipped_note(80, 15) == "Loaded the first 80 of 95 files."
  end

  test "Loading again keeps the prototype's id", ctx do
    first = loaded(ctx, file_names: ["a.html", "b.html", "c0.html"], file_count: 3)

    assert_decides(
      Project,
      [first],
      load(ctx, prototype_id: ctx.p9, file_names: ["c.html"], total_bytes: 20_000),
      [loaded(ctx, prototype_id: ctx.p1, file_names: ["c.html"], file_count: 1)]
    )

    # ... and the stored files for p-1 are replaced by c.html.
    PrototypeFile.replace!(ctx.p1, [%{name: "a.html", type: "text/html", content: "<p>a"}])
    PrototypeFile.replace!(ctx.p1, [%{name: "c.html", type: "text/html", content: "<p>c"}])
    assert [%{name: "c.html", content: "<p>c"}] = PrototypeFile.for_prototype!(ctx.p1)
  end

  @tag skip:
         "Needs Member roles (MemberRoleChanged, slice change-role). Until then any signed-in member may load."
  test "Viewers and commenters can't load a prototype (once roles exist)" do
  end

  test "Several files unreadable", ctx do
    rejects(
      ctx,
      [created(ctx)],
      load(ctx, unreadable_file_names: ["a.zip", "b.zip", "c.zip"], total_bytes: 40_000),
      "We couldn't read a.zip, b.zip and c.zip. Check the files and try again."
    )
  end

  test "Several files too large", ctx do
    rejects(
      ctx,
      [created(ctx)],
      load(ctx,
        file_names: ["a.html", "b.html"],
        too_large_file_names: ["a.html", "b.html"],
        total_bytes: 52_000_000
      ),
      "a.html and b.html are larger than 20 MB. Remove embedded videos or large images and try again."
    )
  end

  test "Unreadable beats too large", ctx do
    rejects(
      ctx,
      [created(ctx)],
      load(ctx,
        file_names: ["big.html"],
        unreadable_file_names: ["broken.zip"],
        too_large_file_names: ["big.html"],
        total_bytes: 26_000_000
      ),
      "We couldn't read broken.zip. Check the file and try again."
    )
  end

  test "Too large beats too much in one load", ctx do
    rejects(
      ctx,
      [created(ctx)],
      load(ctx,
        file_names: ["big.html" | pages(1..60)],
        too_large_file_names: ["big.html"],
        total_bytes: 130_000_000
      ),
      "big.html is larger than 20 MB. Remove embedded videos or large images and try again."
    )
  end

  test "No such project", ctx do
    rejects(
      ctx,
      [],
      load(ctx, file_names: ["a.html"], total_bytes: 40_000),
      "That project doesn't exist."
    )
  end

  test "Deleted project", ctx do
    deleted = %ProjectDeleted{project_id: ctx.pr, deleted_by: ctx.u1, deleted_at: @at}

    rejects(
      ctx,
      [created(ctx), deleted],
      load(ctx, file_names: ["a.html"], total_bytes: 40_000),
      "That project doesn't exist."
    )
  end

  # --- the interactive rule (worked out before the command) -----------------

  @app_html """
  <a href="#signin">Sign in</a> <a href="#board">Board</a>
  <section id="signin">…</section><section id="board" hidden>…</section>
  <script>document.querySelectorAll("section").forEach(s => s.hidden = s.id !== location.hash.slice(1))</script>
  """

  test "One HTML file with in-page navigation is interactive" do
    assert %{file_names: ["app.html"], interactive: true} =
             Intake.read([file("app.html", @app_html)])
  end

  test "One HTML file of plain content isn't interactive" do
    about = ~s(<h1>About</h1><p>We make things.</p><img src="team.png">)

    assert %{file_names: ["about.html"], interactive: false} =
             Intake.read([file("about.html", about)])
  end

  test "A set of HTML files is never interactive" do
    assert %{file_names: ["board.html", "home.html"], interactive: false} =
             Intake.read([file("home.html", @app_html), file("board.html", @app_html)])
  end

  test "A large file beyond the first 80 doesn't block the load", ctx do
    files =
      Enum.map(pages(1..89), &file(&1, "<p>x</p>")) ++
        [%{name: "page-90.html", size: 30_000_000, content: nil}]

    read = Intake.read(files)

    # Only the kept files (the first 80 by name) are checked.
    assert read.too_large_file_names == []
    assert length(read.file_names) == 90

    assert_decides(
      Project,
      [created(ctx)],
      load(ctx,
        file_names: read.file_names,
        too_large_file_names: read.too_large_file_names,
        total_bytes: read.total_bytes
      ),
      [loaded(ctx, file_names: pages(1..80), file_count: 80, skipped_count: 10)]
    )

    assert Intake.skipped_note(80, 10) == "Loaded the first 80 of 90 files."
  end

  # --- not model scenarios ----------------------------------------------------

  test "files are sorted into usable, ignored and unreadable, .zip archives opened" do
    {:ok, {_, zip}} =
      :zip.create(~c"proto.zip", [{~c"screens/home.html", "<p>h</p>"}, {~c"README.md", "x"}], [
        :memory
      ])

    read =
      Intake.read([
        file("proto.zip", zip),
        file("broken.zip", "not a zip"),
        file("notes.txt", "x"),
        file("shot.PNG", "png")
      ])

    assert read.file_names == ["home.html", "shot.PNG"]
    assert read.ignored_file_names == ["README.md", "notes.txt"]
    assert read.unreadable_file_names == ["broken.zip"]
  end

  test "a command without loadedBy is refused", ctx do
    rejects(
      ctx,
      [created(ctx)],
      load(ctx, file_names: ["a.html"], loaded_by: nil),
      "Only editors can load a prototype."
    )
  end

  test "PrototypeLoaded survives the event store's JSON round trip", ctx do
    event = loaded(ctx, file_names: ["a.html"], file_count: 1, source: :paste)
    json = event |> Jason.encode!() |> Jason.decode!(keys: :atoms)

    assert JsonDecoder.decode(struct(PrototypeLoaded, json)) == event
  end

  defp file(name, content), do: %{name: name, size: byte_size(content), content: content}
end
