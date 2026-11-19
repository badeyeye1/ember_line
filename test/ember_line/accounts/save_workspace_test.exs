defmodule EmberLine.Accounts.SaveWorkspaceTest do
  @moduledoc "Slice save-workspace: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false

  import EmberLine.Given.Account
  import EmberLine.ScenarioCase

  alias EmberLine.Accounts.Workspace

  @event "WorkspaceDetailsSaved"
  @invalid_url "Use 2 to 39 lowercase letters, numbers or hyphens for the URL."
  @not_allowed "Only owners and admins can change workspace settings."
  @taken "That URL is taken. Try another."

  setup do
    owner = account()
    # Given WorkspaceCreated(workspaceId: w-1, name: Acme, slug: acme)
    workspace = workspace_created(owner, %{name: "Acme", slug: "acme-#{unique()}"})
    %{owner: owner, workspace: workspace}
  end

  defp unique, do: System.unique_integer([:positive])

  defp save(workspace, actor, params) do
    params = Map.put_new(params, :default_stack, "Other")
    Workspace.save_workspace_details(workspace, params, actor: actor)
  end

  defp reloaded(workspace), do: Ash.get!(Workspace, workspace.id, authorize?: false)

  test "Owner renames the workspace", %{owner: owner, workspace: workspace} do
    slug = "acme-labs-#{unique()}"

    assert {:ok, saved} =
             save(workspace, owner, %{name: "Acme Labs", slug: slug, default_stack: "Other"})

    assert {saved.name, saved.slug, saved.default_stack} == {"Acme Labs", slug, "Other"}

    stored = reloaded(workspace)
    assert {stored.name, stored.slug, stored.default_stack} == {"Acme Labs", slug, "Other"}

    [event] = assert_events(@event, workspace.id, 1)
    assert event.stream == "Workspace"

    assert %{
             "workspaceId" => workspace_id,
             "name" => "Acme Labs",
             "slug" => ^slug,
             "defaultStack" => "Other",
             "savedBy" => saved_by,
             "savedAt" => saved_at
           } = event.data

    assert {workspace_id, saved_by} == {workspace.id, owner.id}
    assert {:ok, _at, 0} = DateTime.from_iso8601(saved_at)

    assert Map.keys(event.data) |> Enum.sort() ==
             ~w(defaultStack name savedAt savedBy slug workspaceId)
  end

  test "Name is empty", %{owner: owner, workspace: workspace} do
    assert {:error, error} = save(workspace, owner, %{name: "", slug: workspace.slug})

    assert error_message?(error, "The workspace needs a name.")
    assert reloaded(workspace).name == "Acme"
    assert_events(@event, workspace.id, 0)
  end

  test "Invalid URL", %{owner: owner, workspace: workspace} do
    assert {:error, error} = save(workspace, owner, %{name: "Acme", slug: "Bad_URL!"})

    assert error_message?(error, @invalid_url)
    assert reloaded(workspace).slug == workspace.slug
    assert_events(@event, workspace.id, 0)
  end

  test "Not the owner or an admin", %{workspace: workspace} do
    # Member roles don't exist yet: anyone but the owner is refused.
    editor = account()

    assert {:error, error} = save(workspace, editor, %{name: "Acme 2", slug: workspace.slug})

    assert error_message?(error, @not_allowed)
    assert reloaded(workspace).name == "Acme"
    assert_events(@event, workspace.id, 0)
  end

  test "URL at the length boundaries", %{owner: owner, workspace: workspace} do
    assert {:ok, %{slug: "ab"}} = save(workspace, owner, %{name: "Acme", slug: "ab"})

    [event] = assert_events(@event, workspace.id, 1)
    assert {event.data["slug"], event.data["savedBy"]} == {"ab", owner.id}

    longest = String.duplicate("a", 39)

    assert {:ok, %{slug: ^longest}} =
             save(reloaded(workspace), owner, %{name: "Acme", slug: longest})

    for slug <- ["a", String.duplicate("b", 40)] do
      assert {:error, error} = save(reloaded(workspace), owner, %{name: "Acme", slug: slug})
      assert error_message?(error, @invalid_url)
    end

    assert reloaded(workspace).slug == longest
    assert_events(@event, workspace.id, 2)
  end

  test "URL already taken", %{owner: owner, workspace: workspace} do
    other = workspace_created(account(), %{name: "Acme Labs", slug: "acme-labs-#{unique()}"})

    assert {:error, error} = save(workspace, owner, %{name: "Acme", slug: other.slug})
    assert error_message?(error, @taken)
    assert reloaded(workspace).slug == workspace.slug
    assert_events(@event, workspace.id, 0)
  end

  test "Keeping its own URL", %{owner: owner, workspace: workspace} do
    assert {:ok, saved} = save(workspace, owner, %{name: "Acme Inc", slug: workspace.slug})

    assert {saved.name, saved.slug} == {"Acme Inc", workspace.slug}
    [event] = assert_events(@event, workspace.id, 1)
    assert event.data["slug"] == workspace.slug
  end

  test "Stack isn't one of the listed ones", %{owner: owner, workspace: workspace} do
    for stack <- ["Rails", nil] do
      assert {:error, error} =
               save(workspace, owner, %{name: "Acme", slug: workspace.slug, default_stack: stack})

      assert error_message?(error, "Pick a stack from the list.")
    end

    assert_events(@event, workspace.id, 0)
  end

  @tag skip:
         "Needs Member roles (MemberRoleChanged, slice change-role). Until then only the owner may save."
  test "Admin saves once roles exist" do
  end

  # Not a model scenario: every listed stack is accepted.
  test "every listed stack can be saved", %{owner: owner, workspace: workspace} do
    for stack <- Workspace.stacks() do
      assert {:ok, %{default_stack: ^stack}} =
               save(reloaded(workspace), owner, %{
                 name: "Acme",
                 slug: workspace.slug,
                 default_stack: stack
               })
    end

    assert length(Workspace.stacks()) == 7
  end

  # Not a model scenario: the unique index is the guarantee when two
  # workspaces race for the same URL; the loser gets the same words.
  test "two workspaces saving the same URL at once: one wins", %{owner: owner} do
    slug = "race-#{unique()}"
    first = workspace_created(owner)
    second = workspace_created(owner)

    results =
      [first, second]
      |> Enum.map(fn workspace ->
        Task.async(fn -> save(workspace, owner, %{name: "Acme", slug: slug}) end)
      end)
      |> Enum.map(&Task.await/1)

    assert [{:error, error}] = Enum.filter(results, &match?({:error, _}, &1))
    assert error_message?(error, @taken)
    assert length(Enum.filter(results, &match?({:ok, _}, &1))) == 1
  end

  # Not a model scenario: the actor comes from the session; nobody acts anonymously.
  test "saving needs a signed-in account", %{workspace: workspace} do
    assert {:error, error} =
             Workspace.save_workspace_details(workspace, %{
               name: "Acme 2",
               slug: workspace.slug,
               default_stack: "Other"
             })

    assert error_message?(error, @not_allowed)
    assert_events(@event, workspace.id, 0)
  end
end
