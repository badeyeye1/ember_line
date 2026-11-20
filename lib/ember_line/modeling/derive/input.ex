defmodule EmberLine.Modeling.Derive.Input do
  @moduledoc """
  What Claude receives for derive-model: HTML files and split pages as text,
  screenshots as images (the first 20 by name; the rest are left out with a
  note), and the earlier outline's slices so Claude reuses their ids and
  names. While the prototype is split, only its pages are sent.

  The prompt is the prototype's outline prompt and Event Modeling rules,
  in priv/prompts/derive_outline.txt.
  """

  alias EmberLine.Modeling.{Intake, PrototypeFile, PrototypePage}

  @external_resource prompt_path =
                       Path.join([__DIR__, "../../../../priv/prompts/derive_outline.txt"])
  @prompt File.read!(prompt_path)

  @max_images 20
  @max_source_bytes 240_000

  @type t :: %{
          prompt: String.t(),
          images: [EmberLine.Modeling.Derive.Claude.image()],
          source_bytes: non_neg_integer(),
          reading: String.t()
        }

  @doc """
  What to send for the project's prototype (its PrototypeScreens entry),
  with the earlier outline's slices (`[]` on a first derive).
  """
  @spec build(map(), [map()]) :: t()
  def build(%{is_split: true} = screens, earlier_slices) do
    pages = PrototypePage.for_prototype!(screens.prototype_id, authorize?: false)
    named = Enum.zip(page_file_names(pages), pages)

    source =
      Enum.map_join(named, "\n\n", fn {name, page} -> "=== FILE: #{name} ===\n#{page.html}" end)

    listed =
      Enum.map_join(named, "; ", fn {name, page} ->
        "#{name} (#{if page.role in [nil, ""], do: "", else: page.role <> ": "}#{page.title})"
      end)

    note =
      "\n\nEach HTML file is a snapshot of ONE page of the running prototype, captured while viewing as a given role. " <>
        ~s(File names are "<role>--<page>.html". Treat each file as one screen and use its exact file name as the screen's "source" ) <>
        "(reach steps are [] for every screen). Pages that several roles share can share slices; name the actor after the role. " <>
        "Snapshots have no scripts, so infer behaviour from headings, labels, buttons, forms, tables and messages.\n" <>
        "Pages: #{listed}"

    %{
      prompt: prompt(note, earlier_slices, source),
      images: [],
      source_bytes: byte_size(source),
      reading: count(length(pages), "page")
    }
  end

  def build(screens, earlier_slices) do
    files = PrototypeFile.for_prototype!(screens.prototype_id, authorize?: false)
    {shots, html} = Enum.split_with(files, &Intake.screenshot?(&1.name))
    {sent, left_out} = Enum.split(shots, @max_images)
    source = Enum.map_join(html, "\n\n", &"=== FILE: #{&1.name} ===\n#{&1.content}")

    %{
      prompt: prompt(screenshots_note(sent, left_out), earlier_slices, source),
      images: for(s <- sent, do: %{media_type: s.type, data: s.content}),
      source_bytes: byte_size(source),
      reading: count(length(files), "file")
    }
  end

  @doc "Whether the text to send is over 240,000 bytes."
  def too_large?(%{source_bytes: bytes}), do: bytes > @max_source_bytes

  defp prompt(note, earlier_slices, source) do
    @prompt <>
      note <>
      earlier(earlier_slices) <>
      if(source == "", do: "", else: "\n\nPROTOTYPE SOURCE:\n\n" <> source)
  end

  defp screenshots_note([], _left_out), do: ""

  defp screenshots_note(sent, left_out) do
    listed = sent |> Enum.with_index(1) |> Enum.map_join("; ", fn {s, i} -> "#{i}. #{s.name}" end)

    more =
      case length(left_out) do
        0 -> ""
        1 -> " 1 more screenshot was left out."
        n -> " #{n} more screenshots were left out."
      end

    "\n\nScreenshots attached, in this order: #{listed}.#{more}"
  end

  defp earlier([]), do: ""

  defp earlier(slices) do
    kept =
      Enum.map(slices, fn s ->
        Map.take(s, ["id", "name", "pattern", "command", "produces", "reads", "readModel"])
      end)

    "\n\nTHIS PROJECT ALREADY HAS A MODEL (from its codebase or earlier work). Keep these slices: " <>
      "reuse their exact ids and names (and their command, event and read model names) wherever the prototype " <>
      "shows the same behaviour, and add new slices only for what isn't there yet.\n" <>
      String.slice(Jason.encode!(kept), 0, 60_000)
  end

  # "<role>--<page>.html", as the prototype names split pages; unique.
  defp page_file_names(pages) do
    {names, _seen} =
      Enum.map_reduce(pages, MapSet.new(), fn page, seen ->
        base =
          [page.role, page.title]
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.map_join("--", &slug/1)

        name = unique(base, seen, 1)
        {name, MapSet.put(seen, name)}
      end)

    names
  end

  defp unique(base, seen, n) do
    name = if n == 1, do: "#{base}.html", else: "#{base}-#{n}.html"
    if MapSet.member?(seen, name), do: unique(base, seen, n + 1), else: name
  end

  defp slug(text) do
    case text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-") do
      "" -> "page"
      slug -> slug
    end
  end

  defp count(1, noun), do: "1 #{noun}"
  defp count(n, noun), do: "#{n} #{noun}s"
end
