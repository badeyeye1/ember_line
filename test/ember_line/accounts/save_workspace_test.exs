defmodule EmberLine.Accounts.SaveWorkspaceTest do
  @moduledoc "Slice save-workspace: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false

  import EmberLine.Given.Account
  import EmberLine.ScenarioCase

  alias EmberLine.Accounts.Workspace

  @event "WorkspaceDetailsSaved"
  @invalid_url "Use 2 to 39 lowercase letters, numbers or hyphens for the URL."

  setup do
    owner = account()
    # Given WorkspaceCreated(workspaceId: w-1, name: Acme, slug: acme)
    workspace = workspace_created(owner, %{name: "Acme", slug: "acme-#{unique()}"})
    %{owner: owner, workspace: workspace}
  end

  defp unique, do: System.unique_integer([:positive])

  defp save(workspace, actor, params) do
    Workspace.save_workspace_details(workspace, params, actor: actor)
  end

  defp reloaded(workspace), do: Ash.get!(Workspace, workspace.id, authorize?: false)

  test "Rename workspace", %{owner: owner, workspace: workspace} do
    slug = "acme-labs-#{unique()}"

    assert {:ok, saved} =
             save(workspace, owner, %{name: "Acme Labs", slug: slug, default_stack: "Other"})

    assert {saved.name, saved.slug, saved.default_stack} == {"Acme Labs", slug, "Other"}

    stored = reloaded(workspace)
    assert {stored.name, stored.slug, stored.default_stack} == {"Acme Labs", slug, "Other"}

    [event] = assert_events(@event, workspace.id, 1)
    assert event.stream == "Workspace"

    assert event.data == %{
             "workspaceId" => workspace.id,
             "name" => "Acme Labs",
             "slug" => slug,
             "accountId" => owner.id,
             "title" => nil,
             "defaultStack" => "Other"
           }
  end

  test "Name is empty", %{owner: owner, workspace: workspace} do
    assert {:error, error} =
             save(workspace, owner, %{name: "", slug: workspace.slug, default_stack: "Other"})

    assert error_message?(error, "The workspace needs a name.")
    assert reloaded(workspace).name == "Acme"
    assert_events(@event, workspace.id, 0)
  end

  test "Invalid URL", %{owner: owner, workspace: workspace} do
    assert {:error, error} =
             save(workspace, owner, %{name: "Acme", slug: "Bad_URL!", default_stack: "Other"})

    assert error_message?(error, @invalid_url)
    assert reloaded(workspace).slug == workspace.slug
    assert_events(@event, workspace.id, 0)
  end

  test "Actor is not an admin", %{workspace: workspace} do
    # Member roles don't exist yet: anyone but the owner is not an admin.
    editor = account()

    assert {:error, error} =
             save(workspace, editor, %{
               name: "Acme 2",
               slug: workspace.slug,
               default_stack: "Other"
             })

    assert error_message?(error, "only owners and admins can change workspace settings")
    assert reloaded(workspace).name == "Acme"
    assert_events(@event, workspace.id, 0)
  end

  test "URL at the length boundaries", %{owner: owner, workspace: workspace} do
    assert {:ok, %{slug: "ab"}} =
             save(workspace, owner, %{name: "Acme", slug: "ab", default_stack: "Other"})

    [event] = assert_events(@event, workspace.id, 1)
    assert event.data["slug"] == "ab"
    assert event.data["defaultStack"] == "Other"

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

  # Not a model scenario (spec gap): another workspace already has the URL.
  test "a URL another workspace has is taken", %{owner: owner, workspace: workspace} do
    other = workspace_created(account(), %{slug: "taken-#{unique()}"})

    assert {:error, error} = save(workspace, owner, %{name: "Acme", slug: other.slug})
    assert error_message?(error, "That URL is taken.")
    assert_events(@event, workspace.id, 0)
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
    assert error_message?(error, "That URL is taken.")
    assert length(Enum.filter(results, &match?({:ok, _}, &1))) == 1
  end

  # Not a model scenario: keeping the workspace's own URL isn't "taken".
  test "saving the unchanged URL succeeds", %{owner: owner, workspace: workspace} do
    assert {:ok, saved} =
             save(workspace, owner, %{name: "Acme Studio", slug: workspace.slug})

    assert saved.slug == workspace.slug
    assert_events(@event, workspace.id, 1)
  end

  # Not a model scenario: the actor comes from the session; nobody acts anonymously.
  test "saving needs a signed-in account", %{workspace: workspace} do
    assert {:error, error} =
             Workspace.save_workspace_details(workspace, %{name: "Acme 2", slug: workspace.slug})

    assert error_message?(error, "only owners and admins can change workspace settings")

    assert_events(@event, workspace.id, 0)
  end
end
