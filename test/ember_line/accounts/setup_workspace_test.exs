defmodule EmberLine.Accounts.SetupWorkspaceTest do
  @moduledoc "Slice setup-workspace: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false

  import EmberLine.Given.Account
  import EmberLine.ScenarioCase

  alias EmberLine.Accounts.{User, Workspace}

  setup do
    {owner, _code} = account_registered(full_name: "Alex Rivera")
    # Given WorkspaceCreated(workspaceId: w-1)
    workspace =
      workspace_created(owner, %{
        name: "Alex's workspace",
        slug: "w-#{System.unique_integer([:positive])}"
      })

    %{owner: owner, workspace: workspace}
  end

  defp set_up(workspace, actor, name, title),
    do: Workspace.set_up_workspace(workspace, name, title, actor: actor)

  defp reloaded(%Workspace{id: id}), do: Ash.get!(Workspace, id, authorize?: false)
  defp reloaded(%User{id: id}), do: Ash.get!(User, id, authorize?: false)

  defp assert_saved(workspace, owner, name, slug, title) do
    details = List.last(events("WorkspaceDetailsSaved", workspace.id))
    assert details, "no WorkspaceDetailsSaved recorded"

    assert %{
             "workspaceId" => wid,
             "name" => ^name,
             "slug" => ^slug,
             "savedBy" => saved_by,
             "savedAt" => _
           } =
             details.data

    assert {wid, saved_by} == {workspace.id, owner.id}
    assert Map.has_key?(details.data, "defaultStack")
    refute Map.has_key?(details.data, "title")

    profile = List.last(events("ProfileSaved", owner.id))
    assert profile, "no ProfileSaved recorded"

    assert profile.data == %{
             "accountId" => owner.id,
             "fullName" => "Alex Rivera",
             "title" => title,
             "timeZone" => nil,
             "avatarColor" => owner.avatar_color
           }

    assert {reloaded(workspace).name, reloaded(workspace).slug} == {name, slug}
    assert reloaded(owner).title == title
  end

  test "Name the workspace and pick a role", %{owner: owner, workspace: workspace} do
    assert {:ok, _} = set_up(workspace, owner, "Acme Studio", "Product")
    assert_saved(workspace, owner, "Acme Studio", "acme-studio", "Product")
  end

  test "Blank name is rejected", %{owner: owner, workspace: workspace} do
    for blank <- ["   ", ""] do
      assert {:error, error} = set_up(workspace, owner, blank, "Product")
      assert error_message?(error, "Give your workspace a name.")
    end

    assert events("WorkspaceDetailsSaved", workspace.id) == []
    assert events("ProfileSaved", owner.id) == []
  end

  test "Punctuation becomes hyphens in the web address", %{owner: owner, workspace: workspace} do
    assert {:ok, _} = set_up(workspace, owner, "Acme & Co!", "Design")
    assert_saved(workspace, owner, "Acme & Co!", "acme-co", "Design")
  end

  test "A name with no letters or digits falls back to a default web address",
       %{owner: owner, workspace: workspace} do
    assert {:ok, _} = set_up(workspace, owner, "!!!", "Something else")
    assert_saved(workspace, owner, "!!!", "workspace", "Something else")
  end

  test "Saving again overwrites the earlier details", %{owner: owner, workspace: workspace} do
    assert {:ok, _} = set_up(workspace, owner, "Acme Studio", "Product")
    assert {:ok, _} = set_up(reloaded(workspace), owner, "Acme Labs", "Engineering")

    assert_saved(workspace, owner, "Acme Labs", "acme-labs", "Engineering")
    assert length(events("WorkspaceDetailsSaved", workspace.id)) == 2
  end

  test "Name's web address already taken", %{owner: owner, workspace: workspace} do
    workspace_created(account(), %{name: "Acme Studio", slug: "acme-studio"})

    assert {:ok, _} = set_up(workspace, owner, "Acme Studio", "Product")
    assert_saved(workspace, owner, "Acme Studio", "acme-studio-2", "Product")
  end

  # Not a model scenario: setting up the same name again keeps the
  # workspace's own web address (it isn't "taken" by itself).
  test "the same name again keeps its own web address", %{owner: owner, workspace: workspace} do
    assert {:ok, _} = set_up(workspace, owner, "Acme Studio", "Product")
    assert {:ok, _} = set_up(reloaded(workspace), owner, "Acme Studio", "Design")
    assert reloaded(workspace).slug == "acme-studio"
  end

  # Not a model scenario: the role must be one of the four listed.
  test "an unknown role is refused", %{owner: owner, workspace: workspace} do
    assert {:error, _} = set_up(workspace, owner, "Acme Studio", "Astronaut")
    assert events("WorkspaceDetailsSaved", workspace.id) == []
  end

  # Not a model scenario: only the workspace's owner sets it up.
  test "someone else can't set up the workspace", %{workspace: workspace} do
    {other, _code} = account_registered()

    assert {:error, error} = set_up(workspace, other, "Hijack", "Product")
    assert error_message?(error, "Only owners and admins can change workspace settings.")
    assert reloaded(workspace).name == "Alex's workspace"
  end
end
