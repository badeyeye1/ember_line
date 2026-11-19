defmodule EmberLine.Accounts.Validations.WorkspaceSlugValid do
  @moduledoc """
  save-workspace rules for the workspace's web address (slug):

    * "Invalid URL" and "URL at the length boundaries": 2 to 39 lowercase
      letters, numbers or hyphens;
    * "URL already taken" (and "Keeping its own URL" is fine): checked up
      front for the message; the `unique_slug` index is the guarantee when
      two saves race, and `handle_identity_error/2` gives that case the same
      words.
  """
  use Ash.Resource.Validation
  require Ash.Query

  alias Ash.Error.Changes.InvalidAttribute
  alias EmberLine.Accounts.Workspace

  @format ~r/\A[a-z0-9-]{2,39}\z/
  @invalid "Use 2 to 39 lowercase letters, numbers or hyphens for the URL."
  @taken "That URL is taken. Try another."

  @impl true
  def validate(changeset, _opts, _context) do
    slug = Ash.Changeset.get_attribute(changeset, :slug)

    cond do
      not (is_binary(slug) and Regex.match?(@format, slug)) ->
        {:error, field: :slug, message: @invalid}

      taken?(slug, changeset.data.id) ->
        {:error, field: :slug, message: @taken}

      true ->
        :ok
    end
  end

  @doc "error_handler for :save_workspace_details: the unique index fired."
  def handle_identity_error(changeset, %{errors: errors} = error) when is_list(errors) do
    %{error | errors: Enum.map(errors, &handle_identity_error(changeset, &1))}
  end

  def handle_identity_error(_changeset, %InvalidAttribute{field: :slug} = error) do
    if error.message == "has already been taken",
      do: InvalidAttribute.exception(field: :slug, message: @taken),
      else: error
  end

  def handle_identity_error(_changeset, error), do: error

  defp taken?(slug, own_id) do
    Workspace
    |> Ash.Query.filter(slug == ^slug and id != ^own_id)
    |> Ash.exists?(authorize?: false)
  end
end
