defmodule EmberLine.Modeling.DeriveModelTest do
  @moduledoc """
  Slice derive-model: one test per scenario in docs/model.json. The
  aggregate's decisions come first; then the whole flow (Derive model
  pressed, the background job, Claude stubbed with Req.Test).
  """
  use EmberLine.DataCase, async: false
  use EmberLine.EventModelCase

  alias EmberLine.Modeling.{Derivation, Derive, Errors, Intake, PrototypePage, Prototypes}
  alias EmberLine.Modeling.Project
  alias EmberLine.Modeling.Project.{CreateProject, DeleteProject, DeriveModel, ModelDerived}
  alias EmberLine.Modeling.Project.{ProjectCreated, ProjectDeleted, PrototypeLoaded}
  alias EmberLine.Modeling.Projections.ProjectList
  alias EmberLine.Repo

  @at ~U[2026-11-20 10:00:00Z]
  @stack "Elixir: Phoenix LiveView + Ash + AshCommanded"

  # The aggregate

  describe "the aggregate" do
    setup do
      %{p1: Ecto.UUID.generate(), pr1: Ecto.UUID.generate(), u1: Ecto.UUID.generate()}
    end

    defp created(ctx), do: %ProjectCreated{project_id: ctx.p1, name: "Studio Workshops"}

    defp loaded(ctx),
      do: %PrototypeLoaded{
        prototype_id: ctx.pr1,
        project_id: ctx.p1,
        file_names: ["board.html", "home.html", "settings.html"],
        file_count: 3,
        interactive: false
      }

    defp derive(ctx, fields \\ []) do
      struct!(
        DeriveModel,
        Map.merge(
          %{
            derivation_id: "d-1",
            project_id: ctx.p1,
            prototype_id: ctx.pr1,
            stack: @stack,
            app_name: "Studio Workshops",
            screen_count: 3,
            slice_count: 24,
            outcome_count: 5,
            slice_ids: ["s-1"],
            not_in_new_outline: [],
            derived_by: ctx.u1,
            derived_at: @at
          },
          Map.new(fields)
        )
      )
    end

    test "Derive from loaded files", ctx do
      assert_decides(Project, [created(ctx), loaded(ctx)], derive(ctx), [
        %ModelDerived{
          derivation_id: "d-1",
          project_id: ctx.p1,
          prototype_id: ctx.pr1,
          stack: @stack,
          app_name: "Studio Workshops",
          screen_count: 3,
          slice_count: 24,
          outcome_count: 5,
          slice_ids: ["s-1"],
          not_in_new_outline: [],
          derived_by: ctx.u1,
          derived_at: @at
        }
      ])
    end

    test "Project with no stack derives as Other", ctx do
      %ModelDerived{stack: "Other"} =
        Project.execute(
          Enum.reduce([created(ctx), loaded(ctx)], %Project{}, &Project.apply(&2, &1)),
          derive(ctx, stack: "Other")
        )
    end

    test "No prototype to derive from", ctx do
      assert_decides(Project, [created(ctx)], derive(ctx), {:error, :nothing_to_derive})

      assert Errors.message(:nothing_to_derive) ==
               "Upload the prototype first, then derive the model."
    end

    test "Stack isn't one of the listed ones", ctx do
      assert_decides(
        Project,
        [created(ctx), loaded(ctx)],
        derive(ctx, stack: "Rails"),
        {:error, :stack_not_listed}
      )
    end

    test "No such project", ctx do
      assert_decides(Project, [], derive(ctx), {:error, :project_not_found})
    end

    test "Deleted project", ctx do
      assert_decides(
        Project,
        [created(ctx), loaded(ctx), %ProjectDeleted{project_id: ctx.p1}],
        derive(ctx),
        {:error, :project_not_found}
      )
    end

    test "Viewers and commenters can't derive (once roles exist)", ctx do
      # Until Member roles exist, "allowed" means signed in.
      assert_decides(
        Project,
        [created(ctx), loaded(ctx)],
        derive(ctx, derived_by: nil),
        {:error, :derive_not_allowed}
      )

      assert Errors.message(:derive_not_allowed) == "Only editors can derive the model."
    end
  end

  # The whole flow: Derive model pressed, the job, Claude stubbed.

  describe "deriving" do
    setup do
      account = Ecto.UUID.generate()
      %{account: account, project_id: create_project!(account, @stack)}
    end

    test "Derive from loaded files", ctx do
      load_files!(ctx, ["board.html", "home.html", "settings.html"])
      stub_claude(answer(screens: 3, slices: 24, outcomes: 5))

      assert {:ok, run} = Derive.start(ctx.project_id, ctx.account)
      assert run.status == :running

      assert run.message ==
               "Claude is reading 3 files and mapping screens, slices and events. This takes a minute or two."

      run_jobs()

      run = Derive.latest_run(ctx.project_id)
      assert run.status == :done
      assert run.message == "Mapped 3 screens into 24 slices."

      assert [%ModelDerived{} = derived] = model_derived(ctx)
      assert derived.derivation_id == run.derivation_id
      assert derived.app_name == "Studio Workshops"
      assert {derived.screen_count, derived.slice_count, derived.outcome_count} == {3, 24, 5}
      assert derived.stack == @stack
      assert derived.derived_by == ctx.account
      assert derived.not_in_new_outline == []

      # The outline is stored under the derivation id.
      outline = Derivation.get!(run.derivation_id)
      assert Enum.map(outline.slices, & &1["id"]) == derived.slice_ids
      assert length(outline.screens) == 3
      assert length(outline.outcomes) == 5
      assert outline.app["name"] == "Studio Workshops"
    end

    test "Derive from split pages", ctx do
      prototype_id = load_files!(ctx, ["app.html"], interactive: true)
      split!(ctx, prototype_id, 12)
      test_pid = self()

      stub_claude(fn body ->
        send(test_pid, {:claude, body})
        answer(screens: 12, slices: 12, outcomes: 3)
      end)

      assert {:ok, run} = Derive.start(ctx.project_id, ctx.account)

      assert run.message ==
               "Claude is reading 12 pages and mapping screens, slices and events. This takes a minute or two."

      run_jobs()

      assert_received {:claude, body}
      text = prompt_text(body)
      assert length(String.split(text, "=== FILE: ")) - 1 == 12
      refute text =~ "=== FILE: app.html"
      assert text =~ "Each HTML file is a snapshot of ONE page"
      assert [%ModelDerived{screen_count: 12}] = model_derived(ctx)
    end

    test "One file, one screen", ctx do
      load_files!(ctx, ["home.html"])
      stub_claude(answer(screens: 1, slices: 1, outcomes: 5))

      assert {:ok, run} = Derive.start(ctx.project_id, ctx.account)

      assert run.message ==
               "Claude is reading 1 file and mapping screens, slices and events. This takes a minute or two."

      run_jobs()
      assert Derive.latest_run(ctx.project_id).message == "Mapped 1 screen into 1 slice."
    end

    test "Screenshots go as images, the first 20 by name", ctx do
      shots = for n <- 1..22, do: "shot-#{String.pad_leading("#{n}", 2, "0")}.png"
      load_files!(ctx, ["home.html" | shots])
      test_pid = self()

      stub_claude(fn body ->
        send(test_pid, {:claude, body})
        answer(screens: 1, slices: 1, outcomes: 1)
      end)

      {:ok, _run} = Derive.start(ctx.project_id, ctx.account)
      run_jobs()

      assert_received {:claude, %{"messages" => [%{"content" => content}]} = body}
      images = for %{"type" => "image"} = image <- content, do: image
      assert length(images) == 20
      assert prompt_text(body) =~ "shot-20.png"
      refute prompt_text(body) =~ "shot-21.png;"
      assert prompt_text(body) =~ "2 more screenshots were left out"
    end

    test "No prototype to derive from", ctx do
      assert Derive.start(ctx.project_id, ctx.account) == {:error, :nothing_to_derive}
      assert Derive.latest_run(ctx.project_id) == nil
    end

    test "Too large to derive in one go", ctx do
      big = ~s(<a href="#b">B</a><section id="b"></section>) <> String.duplicate("x", 900_000)
      {:ok, _} = Prototypes.load(ctx.project_id, :paste, Intake.paste(big), ctx.account)

      assert Derive.start(ctx.project_id, ctx.account) == {:error, :too_large_to_derive}

      assert Errors.message(:too_large_to_derive) ==
               "This prototype is too large to derive in one go. Split it into pages first."
    end

    for {how, response} <- [
          {"rate limited", {429, "rate_limit_error"}},
          {"a 5xx", {500, "api_error"}},
          {"overloaded", {529, "overloaded_error"}},
          {"timed out", :timeout}
        ] do
      test "Claude unavailable: #{how}", ctx do
        load_files!(ctx, ["board.html", "home.html", "settings.html"])
        stub_failure(unquote(Macro.escape(response)))

        {:ok, _run} = Derive.start(ctx.project_id, ctx.account)
        run_jobs()

        run = Derive.latest_run(ctx.project_id)
        assert run.status == :failed
        assert run.message == "Claude can't be reached right now. Try again in a minute."
        assert model_derived(ctx) == []
      end
    end

    for {how, text} <- [
          {"not the outline", "Sorry, I can't help with that."},
          {"no slices", ~s({"app":{"name":"X"},"screens":[],"slices":[]})}
        ] do
      test "Claude's answer can't be read: #{how}", ctx do
        load_files!(ctx, ["board.html", "home.html", "settings.html"])
        stub_claude(unquote(text))

        {:ok, _run} = Derive.start(ctx.project_id, ctx.account)
        run_jobs()

        run = Derive.latest_run(ctx.project_id)
        assert run.status == :failed
        assert run.message == "Claude's answer couldn't be read. Press Derive model to try again."
        assert model_derived(ctx) == []
        assert Derivation.get(run.derivation_id) == nil
      end
    end

    test "Stopped while running", ctx do
      load_files!(ctx, ["board.html", "home.html", "settings.html"])
      stub_claude(answer(screens: 3, slices: 24, outcomes: 5))

      {:ok, run} = Derive.start(ctx.project_id, ctx.account)
      assert {:ok, stopped} = Derive.stop(run.derivation_id)
      assert stopped.status == :stopped
      assert stopped.message == "Stopped."

      run_jobs()

      assert Derive.latest_run(ctx.project_id).status == :stopped
      assert model_derived(ctx) == []
    end

    test "Derived again: new slices are added, earlier ones kept", ctx do
      load_files!(ctx, ["board.html", "home.html", "settings.html"])
      stub_claude(answer(screens: 3, slices: 24, outcomes: 5))
      {:ok, first} = Derive.start(ctx.project_id, ctx.account)
      run_jobs()

      earlier = Derivation.get!(first.derivation_id).slices
      test_pid = self()

      # The new outline keeps the first 19 by id, the 20th by name on the same
      # screen, adds two, and leaves out the last four.
      [twentieth | _] = Enum.drop(earlier, 19)

      kept =
        for s <- Enum.take(earlier, 19),
            do: %{
              "id" => s["id"],
              "name" => s["name"],
              "pattern" => "state_view",
              "screen" => s["screen"]
            }

      renamed = %{
        "id" => "fresh-kebab-id",
        "name" => String.upcase(twentieth["name"]),
        "pattern" => "state_view",
        "screen" => twentieth["screen"]
      }

      new =
        for n <- [25, 26],
            do: %{
              "id" => "slice-#{n}",
              "name" => "Slice #{n}",
              "pattern" => "state_change",
              "screen" => "screen-1"
            }

      stub_claude(fn body ->
        send(test_pid, {:claude, body})
        answer(screens: 3, slices: kept ++ [renamed | new], outcomes: 5)
      end)

      {:ok, second} = Derive.start(ctx.project_id, ctx.account)
      run_jobs()

      # The earlier slices are sent so Claude reuses their ids and names.
      assert_received {:claude, body}
      assert prompt_text(body) =~ "THIS PROJECT ALREADY HAS A MODEL"
      assert prompt_text(body) =~ hd(earlier)["id"]

      assert [_first, %ModelDerived{} = again] = model_derived(ctx)
      assert again.slice_count == 22
      assert Enum.take(again.slice_ids, 20) == Enum.map(Enum.take(earlier, 20), & &1["id"])
      assert again.not_in_new_outline == Enum.map(Enum.drop(earlier, 20), & &1["id"])

      assert Derive.latest_run(ctx.project_id).message ==
               "Mapped 3 screens into 22 slices. 4 slices from before aren't in the new model: review them on the board."

      assert Derive.latest_run(ctx.project_id).derivation_id == second.derivation_id
    end

    test "Stack isn't one of the listed ones", ctx do
      load_files!(ctx, ["board.html", "home.html", "settings.html"])

      Repo.update_all(
        from(p in ProjectList, where: p.project_id == ^ctx.project_id),
        set: [stack: "Rails"]
      )

      assert Derive.start(ctx.project_id, ctx.account) == {:error, :stack_not_listed}
    end

    test "Project with no stack derives as Other", ctx do
      project_id = create_project!(ctx.account, nil)
      ctx = %{ctx | project_id: project_id}
      load_files!(ctx, ["board.html", "home.html", "settings.html"])
      stub_claude(answer(screens: 3, slices: 24, outcomes: 5))

      {:ok, _run} = Derive.start(project_id, ctx.account)
      run_jobs()

      assert [%ModelDerived{stack: "Other"}] = model_derived(ctx)
    end

    test "No such project", ctx do
      assert Derive.start(Ecto.UUID.generate(), ctx.account) == {:error, :project_not_found}
    end

    test "Deleted project", ctx do
      load_files!(ctx, ["board.html"])

      dispatch!(%DeleteProject{
        project_id: ctx.project_id,
        deleted_by: ctx.account,
        confirmed: true,
        deleted_at: @at
      })

      assert Derive.start(ctx.project_id, ctx.account) == {:error, :project_not_found}
    end

    test "Viewers and commenters can't derive (once roles exist)", ctx do
      load_files!(ctx, ["board.html"])
      assert Derive.start(ctx.project_id, nil) == {:error, :derive_not_allowed}
    end
  end

  # Helpers

  defp create_project!(account, stack) do
    project_id = Ecto.UUID.generate()

    dispatch!(%CreateProject{
      project_id: project_id,
      name: "Studio Workshops",
      source_type: :new,
      stack: stack,
      created_by: account,
      workspace_id: Ecto.UUID.generate(),
      created_at: @at
    })

    project_id
  end

  defp load_files!(ctx, names, opts \\ []) do
    files =
      for name <- names do
        content =
          cond do
            String.ends_with?(name, ".png") -> "png"
            opts[:interactive] -> ~s(<a href="#b">B</a><section id="b"></section>)
            true -> "<h1>#{name}</h1>"
          end

        %{name: name, size: byte_size(content), content: content}
      end

    {:ok, %{prototype_id: prototype_id}} =
      Prototypes.load(ctx.project_id, :files, Intake.read(files), ctx.account)

    prototype_id
  end

  defp split!(ctx, prototype_id, count) do
    pages =
      for n <- 1..count,
          do: %{
            title: "Page #{n}",
            role: if(n <= 6, do: "Host", else: "Member"),
            route: "#p#{n}",
            html: "<h1>Page #{n}</h1>"
          }

    {:ok, _} = Prototypes.split(ctx.project_id, prototype_id, pages, count, 2, false, ctx.account)
    assert length(PrototypePage.for_prototype!(prototype_id)) == count
  end

  defp run_jobs, do: Oban.drain_queue(queue: :derive)

  defp model_derived(ctx) do
    EmberLine.CommandedApp
    |> Commanded.EventStore.stream_forward("project-" <> ctx.project_id)
    |> case do
      {:error, :stream_not_found} -> []
      stream -> for %{data: %ModelDerived{} = e} <- stream, do: e
    end
  end

  defp prompt_text(%{"messages" => [%{"content" => content}]}),
    do: Enum.map_join(content, "\n", &Map.get(&1, "text", ""))

  # An outline as Claude writes it.
  defp answer(opts) do
    screens =
      for n <- 1..opts[:screens],
          do: %{"id" => "screen-#{n}", "name" => "Screen #{n}", "source" => "f.html"}

    slices =
      case opts[:slices] do
        n when is_integer(n) ->
          for i <- 1..n,
              do: %{
                "id" => "slice-#{i}",
                "name" => "Slice #{i}",
                "pattern" => "state_view",
                "screen" => "screen-#{rem(i - 1, opts[:screens]) + 1}"
              }

        list ->
          list
      end

    outcomes =
      for n <- 1..opts[:outcomes],
          do: %{"id" => "outcome-#{n}", "name" => "Outcome #{n}", "slices" => [hd(slices)["id"]]}

    Jason.encode!(%{
      "app" => %{"name" => "Studio Workshops", "summary" => "Workshops."},
      "screens" => screens,
      "streams" => %{"WorkshopScheduled" => "Workshop"},
      "outcomes" => outcomes,
      "slices" => slices
    })
  end

  defp stub_claude(text) when is_binary(text), do: stub_claude(fn _body -> text end)

  defp stub_claude(fun) do
    Req.Test.stub(EmberLine.Modeling.Derive.Claude, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn, length: 50_000_000)
      text = fun.(Jason.decode!(raw))

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, sse(text))
    end)
  end

  defp stub_failure(:timeout) do
    Req.Test.stub(EmberLine.Modeling.Derive.Claude, &Req.Test.transport_error(&1, :timeout))
  end

  defp stub_failure({status, type}) do
    Req.Test.stub(EmberLine.Modeling.Derive.Claude, fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{"type" => "error", "error" => %{"type" => type, "message" => "no"}})
    end)
  end

  # The Messages API's server-sent events for one text answer.
  defp sse(text) do
    [
      {"message_start", %{"type" => "message_start", "message" => %{"id" => "msg_1"}}},
      {"content_block_start",
       %{
         "type" => "content_block_start",
         "index" => 0,
         "content_block" => %{"type" => "text", "text" => ""}
       }},
      {"content_block_delta",
       %{
         "type" => "content_block_delta",
         "index" => 0,
         "delta" => %{"type" => "text_delta", "text" => text}
       }},
      {"content_block_stop", %{"type" => "content_block_stop", "index" => 0}},
      {"message_delta", %{"type" => "message_delta", "delta" => %{"stop_reason" => "end_turn"}}},
      {"message_stop", %{"type" => "message_stop"}}
    ]
    |> Enum.map_join(fn {event, data} -> "event: #{event}\ndata: #{Jason.encode!(data)}\n\n" end)
  end
end
