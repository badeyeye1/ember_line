defmodule EmberLine.Modeling.Errors do
  @moduledoc """
  The model's error codes for rejected Project and Slice commands, and the
  words the screens show for them. One place, so screens and tests agree.
  """

  @errors %{
    # create-project
    project_name_required: {"ProjectNameRequired", "Give the project a name."},
    repo_url_required: {"RepoUrlRequired", "Add the GitHub repository URL."},
    not_allowed: {"NotAllowed", "You don't have permission to do that."}
  }

  @doc "The model's error code, e.g. `ProjectNameRequired`."
  def code(reason), do: @errors |> Map.fetch!(reason) |> elem(0)

  @doc "What the screen shows for the error."
  def message(reason) do
    case Map.fetch(@errors, reason) do
      {:ok, {_code, message}} -> message
      :error -> "Something went wrong. Try again."
    end
  end
end
