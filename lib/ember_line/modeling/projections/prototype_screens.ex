defmodule EmberLine.Modeling.Projections.PrototypeScreens do
  @moduledoc """
  Read model PrototypeScreens (slice view-intake): a project's loaded
  prototype, its tabs and the board's notes. Written only by
  `EmberLine.Modeling.Projections.PrototypeScreensProjection`; read-only here.

  `tabs` holds the loaded files. A split's pages are state stored
  (`EmberLine.Modeling.PrototypePage`) and written after
  PrototypeSplitIntoPages, so the projection can't see them; reading a split
  prototype's screens returns one tab per stored page instead.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Modeling,
    data_layer: AshPostgres.DataLayer

  alias EmberLine.Modeling.{Intake, PrototypePage}

  @kinds [:image, :static_html, :live_html, :page]

  postgres do
    table "prototype_screens"
    repo EmberLine.Repo
  end

  code_interface do
    define :read_for_project,
      action: :for_project,
      args: [:project_id],
      get?: true,
      not_found_error?: false
  end

  actions do
    defaults [:read]

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
    end
  end

  attributes do
    attribute :project_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :prototype_id, :uuid, allow_nil?: false, public?: true
    attribute :notes, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :tabs, {:array, :map}, allow_nil?: false, default: [], public?: true
    attribute :file_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :is_split, :boolean, allow_nil?: false, default: false, public?: true
    attribute :page_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :skipped_count, :integer, allow_nil?: false, default: 0, public?: true

    attribute :ignored_file_names, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :interactive, :boolean, allow_nil?: false, default: false, public?: true
    attribute :skipped_page_count, :integer, allow_nil?: false, default: 0, public?: true
    attribute :timed_out, :boolean, allow_nil?: false, default: false, public?: true
    attribute :role_count, :integer, allow_nil?: false, default: 0, public?: true
  end

  @type tab :: %{
          position: pos_integer(),
          label: String.t(),
          kind: :image | :static_html | :live_html | :page,
          source: String.t() | pos_integer()
        }

  @doc """
  The project's prototype screens, with the tabs to show: the loaded files,
  or the stored pages when it's split. Nothing loaded yet reads as an empty
  entry (no tabs, no notes).
  """
  def for_project!(project_id) do
    case read_for_project(project_id, authorize?: false) do
      {:ok, nil} -> struct(__MODULE__, project_id: project_id)
      {:ok, screens} -> with_tabs(screens)
    end
  end

  defp with_tabs(%{is_split: true} = screens) do
    pages = PrototypePage.for_prototype!(screens.prototype_id, authorize?: false)

    %{
      screens
      | tabs:
          for(
            p <- pages,
            do: %{position: p.position, label: page_label(p), kind: :page, source: p.position}
          )
    }
  end

  defp with_tabs(screens), do: %{screens | tabs: Enum.map(screens.tabs, &tab/1)}

  # Stored as JSON: string keys, the kind as a string.
  defp tab(%{"position" => position, "label" => label, "kind" => kind, "source" => source}),
    do: %{position: position, label: label, kind: kind(kind), source: source}

  defp kind(kind) when is_binary(kind), do: Enum.find(@kinds, &(Atom.to_string(&1) == kind))
  defp kind(kind) when kind in @kinds, do: kind

  # "Role · Title", or the title alone with no role picker.
  defp page_label(%{role: role, title: title}) when role in [nil, ""], do: title
  defp page_label(%{role: role, title: title}), do: "#{role} · #{title}"

  @doc "A loaded file's tab: screenshots as images, an interactive file live, other HTML static."
  def file_tab(name, position, interactive) do
    %{position: position, label: name, kind: file_kind(name, interactive), source: name}
  end

  defp file_kind(name, interactive) do
    cond do
      Intake.screenshot?(name) -> :image
      interactive -> :live_html
      true -> :static_html
    end
  end
end
