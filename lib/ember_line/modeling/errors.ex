defmodule EmberLine.Modeling.Errors do
  @moduledoc """
  What the screens show when a Project or Slice command is rejected: each
  reason maps to the exact sentence its scenario gives. One place, so screens
  and tests agree.
  """

  @messages %{
    # create-project
    project_name_required: "Give the project a name.",
    repo_url_required: "Paste the GitHub repository address, like https://github.com/owner/repo.",
    not_allowed: "Only editors and admins can create projects.",
    stack_not_listed: "Pick a stack from the list.",
    source_type_not_listed:
      "Pick where the code comes from: start fresh, a folder on this computer, or GitHub.",
    # delete-project
    delete_not_allowed: "Only editors and admins can delete a project.",
    project_not_found: "That project doesn't exist."
  }

  @doc "What the screen shows for the error."
  def message({:confirm_delete, name}),
    do: "Click Delete again to delete #{name}. This can't be undone."

  def message(reason), do: Map.get(@messages, reason, "Something went wrong. Try again.")
end
