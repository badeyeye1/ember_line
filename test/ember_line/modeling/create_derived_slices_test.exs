defmodule EmberLine.Modeling.CreateDerivedSlicesTest do
  @moduledoc """
  Slice create-derived-slices: one test per scenario in docs/model.json.

  Each test stores an outline (the Derivation record derive-model writes),
  dispatches DeriveModel, and runs the automation's job. "A feature derive
  adds its new slices to that feature" is built with derive-feature.
  """
  use EmberLine.DataCase, async: false
  use EmberLine.EventModelCase

  alias EmberLine.Modeling.{Derivation, DerivationRun, Intake, Prototypes, Slice, Slices}
  alias EmberLine.Modeling.Project.{CreateProject, DeleteProject, DeriveModel}
  alias EmberLine.Modeling.Projections.SlicesToCreate
  alias EmberLine.Modeling.Slice.{AddSlice, SliceAdded}

  @at ~U[2026-11-20 10:00:00Z]
  @stack "Elixir: Phoenix LiveView + Ash + AshCommanded"
  @limit "the board is at the 150 slice limit."

  setup do
    account = Ecto.UUID.generate()
    project_id = create_project!(account)
    %{account: account, project_id: project_id, prototype_id: load_files!(project_id, account)}
  end

  test "Each derived slice is added in order", ctx do
    [s1, s2] = ids(2)

    d1 =
      derive!(ctx, [
        outline_slice(s1, "Create account", "state_change", "signup",
          command: "RegisterAccount",
          produces: ["AccountRegistered"]
        ),
        outline_slice(s2, "Pending verification", "state_view", "verify",
          readModel: "PendingVerification",
          reads: ["AccountRegistered"]
        )
      ])

    assert [{^s1, 1}, {^s2, 2}] =
             for(row <- to_create(ctx), do: {row.slice_id, row.position})

    assert hd(to_create(ctx)).derivation_id == d1

    run_jobs()

    assert [
             %SliceAdded{
               slice_id: ^s1,
               project_id: project_id,
               name: "Create account",
               pattern: "state_change",
               screen_id: "signup",
               position: 1,
               feature_id: nil,
               command_name: "RegisterAccount",
               produces: ["AccountRegistered"],
               reads: [],
               read_model_name: "",
               projection_name: ""
             }
           ] = slice_added(s1)

    assert project_id == ctx.project_id

    assert [
             %SliceAdded{
               slice_id: ^s2,
               name: "Pending verification",
               pattern: "state_view",
               screen_id: "verify",
               position: 2,
               command_name: "",
               read_model_name: "PendingVerification",
               reads: ["AccountRegistered"],
               produces: [],
               projection_name: ""
             }
           ] = slice_added(s2)

    assert to_create(ctx) == []
    assert Slices.count(ctx.project_id) == 2
  end

  test "Derive found no slices", ctx do
    derive!(ctx, [])
    assert to_create(ctx) == []

    run_jobs()

    assert Slices.count(ctx.project_id) == 0
  end

  test "Restarted half way", ctx do
    [s1, s2] = ids(2)

    derive!(ctx, [
      outline_slice(s1, "Create account", "state_change", "signup"),
      outline_slice(s2, "Pending verification", "state_view", "verify")
    ])

    # The job added s-1, then stopped before s-2.
    assert :ok = Slices.add(add_slice(ctx, s1, "Create account", "signup", 1))
    assert [%{slice_id: ^s2}] = to_create(ctx)

    run_jobs()

    assert [%SliceAdded{position: 2}] = slice_added(s2)
    assert [_once] = slice_added(s1)
  end

  @tag skip: "FeatureDerived is produced by derive-feature (Features & boundaries), built with it"
  test "A feature derive adds its new slices to that feature" do
  end

  test "A slice that already exists by name isn't added twice", ctx do
    [s9, s1] = ids(2)

    # Added by hand, so it's in AddedSlices.
    assert :ok = Slices.add(add_slice(ctx, s9, "Create account", "signup", 1))

    derive!(ctx, [outline_slice(s1, "create account", "state_change", "signup")])
    assert to_create(ctx) == []

    run_jobs()

    assert slice_added(s1) == []
    assert Slices.count(ctx.project_id) == 1
  end

  test "The same slice id arrives twice", ctx do
    [s1] = ids(1)
    added = %SliceAdded{slice_id: s1, project_id: ctx.project_id, name: "Create account"}
    command = add_slice(ctx, s1, "Create account", "signup", 1)

    assert_decides(Slice, [added], command, [])

    # Through the app as well: no error, and still one SliceAdded.
    assert :ok = Slices.add(command)
    assert :ok = Slices.add(command)
    assert [_once] = slice_added(s1)
  end

  test "The board fills up part way", ctx do
    board!(ctx, 148)
    [s1, s2, s3, s4, s5] = slices = ids(5)

    d3 =
      derive!(ctx, Enum.map(slices, &outline_slice(&1, "Step #{&1}", "state_change", "home")))

    run_jobs()

    assert [%SliceAdded{position: 149}] = slice_added(s1)
    assert [%SliceAdded{position: 150}] = slice_added(s2)
    assert Enum.all?([s3, s4, s5], &(slice_added(&1) == []))

    assert Ash.get!(DerivationRun, d3).message ==
             "Mapped 1 screen into 5 slices. 3 slices weren't added: " <> @limit
  end

  test "One slice over the limit", ctx do
    board!(ctx, 149)
    [s1, s2] = ids(2)

    d4 =
      derive!(ctx, [
        outline_slice(s1, "One", "state_change", "home"),
        outline_slice(s2, "Two", "state_change", "home")
      ])

    run_jobs()

    assert [%SliceAdded{position: 150}] = slice_added(s1)
    assert slice_added(s2) == []

    assert Ash.get!(DerivationRun, d4).message ==
             "Mapped 1 screen into 2 slices. 1 slice wasn't added: " <> @limit
  end

  test "The project is deleted while slices are being added", ctx do
    [s1, s2, s3] = ids(3)

    d1 =
      derive!(ctx, [
        outline_slice(s1, "One", "state_change", "home"),
        outline_slice(s2, "Two", "state_change", "home"),
        outline_slice(s3, "Three", "state_change", "home")
      ])

    assert :ok = Slices.add(add_slice(ctx, s1, "One", "home", 1))

    dispatch!(%DeleteProject{
      project_id: ctx.project_id,
      deleted_by: ctx.account,
      confirmed: true,
      deleted_at: @at
    })

    run_jobs()

    assert slice_added(s2) == []
    assert slice_added(s3) == []
    # No message: the board is gone.
    assert Ash.get!(DerivationRun, d1).message == "Mapped 1 screen into 3 slices."
  end

  # Helpers

  defp ids(n), do: for(_ <- 1..n, do: Ecto.UUID.generate())

  defp outline_slice(id, name, pattern, screen, details \\ []) do
    Map.merge(
      %{
        "id" => id,
        "name" => name,
        "pattern" => pattern,
        "screen" => screen,
        "command" => nil,
        "produces" => [],
        "reads" => [],
        "readModel" => nil
      },
      Map.new(details, fn {key, value} -> {to_string(key), value} end)
    )
  end

  # derive-model's job, done: the outline stored, the run done, DeriveModel dispatched.
  defp derive!(ctx, slices) do
    derivation_id = Ecto.UUID.generate()
    slices = slices |> Enum.with_index(1) |> Enum.map(fn {s, i} -> Map.put(s, "position", i) end)
    opts = [authorize?: false]

    Derivation.store!(derivation_id, ctx.project_id, %{}, [], %{}, [], slices, @at, opts)

    derivation_id
    |> DerivationRun.start!(ctx.project_id, "Claude is reading…", ctx.account, @at, opts)
    |> DerivationRun.finish!(:done, done_message(length(slices)), opts)

    dispatch!(%DeriveModel{
      derivation_id: derivation_id,
      project_id: ctx.project_id,
      prototype_id: ctx.prototype_id,
      stack: @stack,
      app_name: "Studio Workshops",
      screen_count: 1,
      slice_count: length(slices),
      outcome_count: 0,
      slice_ids: Enum.map(slices, & &1["id"]),
      not_in_new_outline: [],
      derived_by: ctx.account,
      derived_at: @at
    })

    derivation_id
  end

  defp done_message(1), do: "Mapped 1 screen into 1 slice."
  defp done_message(n), do: "Mapped 1 screen into #{n} slices."

  defp add_slice(ctx, slice_id, name, screen_id, position) do
    %AddSlice{
      slice_id: slice_id,
      project_id: ctx.project_id,
      name: name,
      pattern: "state_change",
      screen_id: screen_id,
      position: position
    }
  end

  # The board already has `n` slices, added by hand.
  defp board!(ctx, n) do
    for position <- 1..n do
      command = add_slice(ctx, Ecto.UUID.generate(), "Slice #{position}", "home", position)
      assert :ok = Slices.add(command)
    end

    assert Slices.count(ctx.project_id) == n
  end

  defp to_create(ctx), do: SlicesToCreate.for_project!(ctx.project_id, authorize?: false)

  defp slice_added(slice_id) do
    EmberLine.CommandedApp
    |> Commanded.EventStore.stream_forward("slice-" <> slice_id)
    |> case do
      {:error, :stream_not_found} -> []
      stream -> for %{data: %SliceAdded{} = e} <- stream, do: e
    end
  end

  defp run_jobs, do: Oban.drain_queue(queue: :derive, with_recursion: true)

  defp create_project!(account) do
    project_id = Ecto.UUID.generate()

    dispatch!(%CreateProject{
      project_id: project_id,
      name: "Studio Workshops",
      source_type: :new,
      stack: @stack,
      created_by: account,
      workspace_id: Ecto.UUID.generate(),
      created_at: @at
    })

    project_id
  end

  defp load_files!(project_id, account) do
    files = [%{name: "home.html", size: 15, content: "<h1>Home</h1>"}]
    {:ok, %{prototype_id: id}} = Prototypes.load(project_id, :files, Intake.read(files), account)
    id
  end
end
