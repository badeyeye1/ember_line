defmodule EmberLine.Modeling.PrototypeFile do
  @moduledoc """
  A loaded prototype's files (slice load-prototype), state stored and keyed
  by prototypeId: name, type, content. PrototypeLoaded names them; their
  content never goes in an event. Loading again replaces them all.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Modeling,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "prototype_files"
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
      prepare build(sort: [name: :asc])
    end

    create :store do
      accept [:prototype_id, :name, :type, :content]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :prototype_id, :uuid, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :type, :string,
      allow_nil?: false,
      constraints: [match: ~r{^(text/html|image/png|image/jpeg|image/webp)$}],
      public?: true

    attribute :content, :binary, allow_nil?: false, public?: true
  end

  identities do
    identity :name_in_prototype, [:prototype_id, :name]
  end

  @doc "Replaces the prototype's stored files with these, in one transaction."
  def replace!(prototype_id, files) do
    EmberLine.Repo.transaction(fn ->
      __MODULE__
      |> Ash.Query.filter(prototype_id == ^prototype_id)
      |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false, strategy: [:atomic, :stream])

      files
      |> Enum.map(&Map.put(&1, :prototype_id, prototype_id))
      |> Ash.bulk_create!(__MODULE__, :store,
        authorize?: false,
        return_errors?: true,
        stop_on_error?: true
      )
    end)

    :ok
  end
end
