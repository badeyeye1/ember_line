defmodule EmberLineWeb.WelcomeLive do
  @moduledoc """
  Screen welcome (docs/design/screens/welcome.*): the Welcome form of slice
  setup-workspace. The owner names their first workspace and says what they
  do; Continue runs SetUpWorkspace and opens the workspace.

  Step 1 of 3: inviting teammates (invite-from-welcome) isn't built yet.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.Workspace

  on_mount {EmberLineWeb.LiveUserAuth, :live_user_required}

  # From docs/design/screens/welcome.html.
  @titles [
    {"Product", "Product", "I shape what gets built"},
    {"Engineering", "Engineering", "I build it"},
    {"Design", "Design", "I design the screens"},
    {"Something else", "Something else", "QA, ops, founder…"}
  ]

  @impl true
  def mount(%{"workspace_id" => workspace_id}, _session, socket) do
    user = socket.assigns.current_user

    case Ash.get(Workspace, workspace_id, actor: user) do
      {:ok, workspace} ->
        {:ok,
         assign(socket,
           page_title: "Welcome",
           workspace: workspace,
           first_name: first_name(user),
           error: nil,
           form:
             to_form(%{"name" => workspace.name, "title" => user.title || "Product"},
               as: :welcome
             )
         )}

      {:error, _} ->
        {:ok,
         socket |> put_flash(:error, "That workspace doesn't exist.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("continue", %{"welcome" => params}, socket) do
    workspace = socket.assigns.workspace

    case Workspace.set_up_workspace(workspace, params["name"], params["title"],
           actor: socket.assigns.current_user
         ) do
      {:ok, _workspace} ->
        {:noreply, push_navigate(socket, to: ~p"/workspaces/#{workspace.id}/projects")}

      {:error, error} ->
        {:noreply, assign(socket, error: message(error), form: to_form(params, as: :welcome))}
    end
  end

  defp message(%{errors: [%{message: message} | _]}) when is_binary(message), do: message
  defp message(_error), do: "Something went wrong. Try again."

  defp first_name(%{full_name: name}) when is_binary(name) and name != "",
    do: name |> String.split(~r/\s+/, trim: true) |> hd()

  defp first_name(_user), do: nil

  @impl true
  def render(assigns) do
    assigns = assign(assigns, titles: @titles)

    ~H"""
    <Layouts.auth flash={@flash}>
      <.steps current={1} total={3} />
      <h1>{if @first_name, do: "Welcome, #{@first_name}", else: "Welcome"}</h1>
      <p class="sub">
        Name your workspace. It's where your team's projects, comments and reviews live.
      </p>

      <.form for={@form} id="welcome-form" phx-submit="continue">
        <.field field={@form[:name]} label="Workspace name" autocomplete="organization" />
        <.choice_cards field={@form[:title]} legend="What do you do?" options={@titles} />
        <.notice :if={@error} tone="err">{@error}</.notice>
        <.button variant="primary" wide type="submit" phx-disable-with="Saving…">Continue</.button>
      </.form>
    </Layouts.auth>
    """
  end
end
