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
    # delete-project and load-prototype
    project_not_found: "That project doesn't exist.",
    # load-prototype
    load_not_allowed: "Only editors can load a prototype.",
    too_much_in_one_load:
      "These files add up to more than 100 MB. Load fewer at a time, or remove large images.",
    no_usable_screens:
      "We couldn't find any screens in those files. Drop HTML files, screenshots or a .zip of the prototype.",
    # split-pages
    split_not_allowed: "Only editors can split a prototype.",
    not_interactive:
      "Load an interactive HTML prototype first: only those can be split into pages.",
    already_split: "This prototype is already split. Undo the split first.",
    prototype_did_not_respond:
      "The prototype didn't respond while it was being split. Reload it and try again.",
    no_pages_found: "No separate pages found. Derive the model from the whole file instead.",
    # undo-split
    undo_split_not_allowed: "Only editors can undo a split.",
    nothing_to_undo: "There's no split to undo.",
    # derive-model
    derive_not_allowed: "Only editors can derive the model.",
    nothing_to_derive: "Upload the prototype first, then derive the model.",
    too_large_to_derive:
      "This prototype is too large to derive in one go. Split it into pages first.",
    claude_unreachable: "Claude can't be reached right now. Try again in a minute.",
    answer_unreadable: "Claude's answer couldn't be read. Press Derive model to try again."
  }

  @doc "What the screen shows for the error."
  def message({:confirm_delete, name}),
    do: "Click Delete again to delete #{name}. This can't be undone."

  def message({:files_unreadable, [name]}),
    do: "We couldn't read #{name}. Check the file and try again."

  def message({:files_unreadable, names}),
    do: "We couldn't read #{names(names)}. Check the files and try again."

  def message({:files_too_large, [name]}),
    do: "#{name} is larger than 20 MB. Remove embedded videos or large images and try again."

  def message({:files_too_large, names}),
    do:
      "#{names(names)} are larger than 20 MB. Remove embedded videos or large images and try again."

  def message(reason), do: Map.get(@messages, reason, "Something went wrong. Try again.")

  @doc ~S|Several names, written "a and b" or "a, b and c".|
  def names([name]), do: name

  def names(names) do
    {init, [last]} = Enum.split(names, -1)
    Enum.join(init, ", ") <> " and " <> last
  end
end
