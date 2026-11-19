defmodule EmberLineWeb.WorkspaceSettingsLive do
  @moduledoc """
  Screen workspace-general: the workspace details card (slice save-workspace).
  Name, web address and default stack, saved with SaveWorkspaceDetails.

  The form is prefilled from the Workspace itself, which only its owner can
  read. The rest of the reference (domains, transfer owner, delete) and
  view-workspace's full read model belong to other slices.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.Validations.CanChangeWorkspaceSettings
  alias EmberLine.Accounts.Workspace

  on_mount {EmberLineWeb.LiveUserAuth, :live_user_required}

  # The messages the screen shows, in the scenarios' words.
  @messages [
    "The workspace needs a name.",
    "Use 2 to 39 lowercase letters, numbers or hyphens for the URL.",
    "That URL is taken. Try another.",
    "Pick a stack from the list.",
    "Only owners and admins can change workspace settings."
  ]

  @impl true
  def mount(%{"workspace_id" => workspace_id}, _session, socket) do
    case Ash.get(Workspace, workspace_id, actor: socket.assigns.current_user) do
      {:ok, workspace} ->
        {:ok,
         socket
         |> assign(page_title: "Workspace settings", saved: false, error: nil)
         |> assign_workspace(workspace)
         |> assign_form(params(workspace), [])}

      {:error, _not_found_or_not_allowed} ->
        {:ok,
         socket
         |> put_flash(:error, CanChangeWorkspaceSettings.message())
         |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("change", %{"workspace" => params}, socket) do
    {:noreply, socket |> assign(saved: false) |> assign_form(params, socket.assigns.form.errors)}
  end

  def handle_event("save", %{"workspace" => params}, socket) do
    input = %{
      name: params["name"],
      slug: params["slug"],
      default_stack: params["default_stack"]
    }

    case Workspace.save_workspace_details(socket.assigns.workspace, input,
           actor: socket.assigns.current_user
         ) do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> assign(saved: true, error: nil)
         |> assign_workspace(workspace)
         |> assign_form(params(workspace), [])}

      {:error, error} ->
        {field_errors, error} = messages(error)

        {:noreply,
         socket
         |> assign(saved: false, error: error)
         |> assign_form(params, field_errors)}
    end
  end

  defp assign_workspace(socket, workspace) do
    assign(socket, workspace: workspace)
  end

  defp params(workspace) do
    %{
      "name" => workspace.name,
      "slug" => workspace.slug,
      "default_stack" => workspace.default_stack || hd(Workspace.stacks())
    }
  end

  defp assign_form(socket, params, errors) do
    assign(socket, form: to_form(params, as: :workspace, errors: errors))
  end

  # Name and URL messages go under their fields; anything else (who may
  # save) shows above the form.
  defp messages(%{errors: errors}) do
    known =
      errors
      |> Enum.filter(&(Map.get(&1, :message) in @messages))
      |> Enum.map(&{error_field(&1), &1.message})
      |> Enum.uniq()

    field_errors =
      for {field, message} <- known, field in [:name, :slug], do: {field, {message, []}}

    error =
      cond do
        field_errors != [] -> nil
        known != [] -> known |> hd() |> elem(1)
        true -> "Something went wrong. Try again."
      end

    {field_errors, error}
  end

  defp error_field(%{field: field}) when is_atom(field) and not is_nil(field), do: field
  defp error_field(%{fields: [field | _]}), do: field
  defp error_field(_error), do: nil

  @impl true
  def render(assigns) do
    assigns = assign(assigns, stacks: Workspace.stacks())

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      workspace={%{id: @workspace.id, name: @workspace.name}}
      nav={:workspace_settings}
      crumbs={[{"Workspace settings", nil}]}
    >
      <section class="ui-page" aria-label="Workspace">
        <.page_header
          title="Workspace settings"
          description={"Settings for everyone in #{@workspace.name}."}
        />
        <div class="ui-pg">
          <.settings_nav current={:workspace_general} workspace_id={@workspace.id} />
          <div class="ui-pg-main">
            <.notice :if={@error} tone="err" id="workspace-error">{@error}</.notice>
            <.form
              for={@form}
              id="workspace-form"
              phx-change="change"
              phx-submit="save"
              novalidate
            >
              <.card title="General">
                <div class="body">
                  <div class="grid gap-3 min-[601px]:grid-cols-2">
                    <.field field={@form[:name]} label="Workspace name" autocomplete="off" />
                    <.slug_field field={@form[:slug]} />
                  </div>
                  <.field
                    field={@form[:default_stack]}
                    type="select"
                    label="Default stack for new projects"
                    options={Enum.map(Workspace.stacks(), &{&1, &1})}
                  />
                </div>
                <:footer>
                  <span class="ui-hint" id="workspace-saved" role="status">
                    {if @saved, do: "Saved."}
                  </span>
                  <.button variant="primary" type="submit" phx-disable-with="Saving…">
                    Save changes
                  </.button>
                </:footer>
              </.card>
            </.form>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  # The URL field: the address prefix, then the slug.
  defp slug_field(assigns) do
    assigns =
      assign(
        assigns,
        :errors,
        if(Phoenix.Component.used_input?(assigns.field),
          do: Enum.map(assigns.field.errors, &elem(&1, 0)),
          else: []
        )
      )

    ~H"""
    <label class="ui-fld" for={@field.id}>
      Workspace URL
      <span class="flex items-center gap-2">
        <span class="ui-hint whitespace-nowrap">emberline.app/</span>
        <input
          type="text"
          id={@field.id}
          name={@field.name}
          value={@field.value}
          class="ui-in min-w-0 flex-1"
          autocomplete="off"
          aria-invalid={@errors != [] && "true"}
        />
      </span>
      <p :for={error <- @errors} class="ui-ferr">{error}</p>
    </label>
    """
  end
end
