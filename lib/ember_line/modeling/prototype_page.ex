defmodule EmberLine.Modeling.PrototypePage do
  @moduledoc """
  A split prototype's pages (slice split-pages), state stored and keyed by
  prototypeId: title, role, route, html and position (the order found).
  PrototypeSplitIntoPages counts them; they never go in an event. A new split
  replaces them; a new load or an undone split removes them.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Modeling,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "prototype_pages"
    repo EmberLine.Repo
  end

  code_interface do
    define :for_prototype, args: [:prototype_id]
  end

  actions do
    defaults [:read, :destroy]

    read :for_prototype do
      argument :prototype_id, :uuid, allow_nil?: false
      filter expr(prototype_id == ^arg(:prototype_id))
      prepare build(sort: [position: :asc])
    end

    create :store do
      accept [:prototype_id, :position, :title, :role, :route, :html]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :prototype_id, :uuid, allow_nil?: false, public?: true
    attribute :position, :integer, allow_nil?: false, constraints: [min: 1], public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :role, :string, public?: true
    attribute :route, :string, public?: true
    attribute :html, :string, allow_nil?: false, public?: true
  end

  identities do
    identity :position_in_prototype, [:prototype_id, :position]
  end

  @doc "Replaces the prototype's stored pages with these, numbered in order, in one transaction."
  def replace!(prototype_id, pages) do
    EmberLine.Repo.transaction(fn ->
      remove!(prototype_id)

      pages
      |> Enum.with_index(1)
      |> Enum.map(fn {page, position} ->
        page
        |> Map.take([:title, :role, :route, :html])
        |> Map.merge(%{prototype_id: prototype_id, position: position})
      end)
      |> Ash.bulk_create!(__MODULE__, :store,
        authorize?: false,
        return_errors?: true,
        stop_on_error?: true
      )
    end)

    :ok
  end

  @doc "Removes the prototype's stored pages."
  def remove!(prototype_id) do
    __MODULE__
    |> Ash.Query.filter(prototype_id == ^prototype_id)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false, strategy: [:atomic, :stream])

    :ok
  end
end
