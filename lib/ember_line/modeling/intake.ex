defmodule EmberLine.Modeling.Intake do
  @moduledoc """
  Reads dropped or pasted prototype files before LoadPrototype is dispatched
  (slice load-prototype), and writes the board's notes.

  Usable files are .html/.htm, .png/.jpg/.webp and .zip archives of those;
  anything else is ignored. Only the kept files (the first 80 usable names)
  are size-checked, counted toward the total and read, so a large file past
  the first 80 never blocks a load. A file over 20 MB isn't read either.
  """

  alias EmberLine.Modeling.Errors
  alias EmberLine.Modeling.Intake.ZipEntry
  alias EmberLine.Modeling.Project.PrototypeLimits

  @types %{
    ".html" => "text/html",
    ".htm" => "text/html",
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".webp" => "image/webp"
  }

  @pasted_name "pasted-prototype.html"

  @typedoc "A dropped file. `content` is nil when the file wasn't uploaded (too large)."
  @type file :: %{name: String.t(), size: non_neg_integer(), content: binary() | nil}

  @type result :: %{
          file_names: [String.t()],
          unreadable_file_names: [String.t()],
          ignored_file_names: [String.t()],
          too_large_file_names: [String.t()],
          total_bytes: non_neg_integer(),
          interactive: boolean(),
          files: [%{name: String.t(), type: String.t(), content: binary()}]
        }

  @doc "Pasted HTML, read as one file named #{@pasted_name}."
  @spec paste(String.t()) :: result()
  def paste(html), do: read([%{name: @pasted_name, size: byte_size(html), content: html}])

  @doc "Sorts the files into usable, ignored and unreadable, and reads the kept ones."
  @spec read([file()]) :: result()
  def read(files) do
    {usable, ignored, unreadable} = Enum.reduce(files, {[], [], []}, &sort_file/2)
    usable = usable |> Enum.reverse() |> Enum.uniq_by(& &1.name)

    {kept_names, _skipped} = usable |> Enum.map(& &1.name) |> PrototypeLimits.kept()
    kept = Enum.filter(usable, &(&1.name in kept_names))
    too_large = for f <- kept, f.size > PrototypeLimits.max_file_bytes(), do: f.name

    total_bytes = kept |> Enum.map(& &1.size) |> Enum.sum()

    # Files are only read when the load can succeed: none too large and the
    # total within 100 MB. An archive entry that holds more than it declares
    # can't be read.
    {read, broken} =
      if too_large == [] and total_bytes <= PrototypeLimits.max_total_bytes() do
        kept
        |> Enum.sort_by(& &1.name)
        |> Enum.map(&{&1, &1.load.()})
        |> Enum.split_with(&match?({_file, {:ok, _content}}, &1))
      else
        {[], []}
      end

    stored =
      for {f, {:ok, content}} <- read, do: %{name: f.name, type: type(f.name), content: content}

    %{
      file_names: usable |> Enum.map(& &1.name) |> Enum.sort(),
      unreadable_file_names: Enum.reverse(unreadable) ++ Enum.map(broken, &elem(&1, 0).name),
      ignored_file_names: Enum.reverse(ignored),
      too_large_file_names: Enum.sort(too_large),
      total_bytes: total_bytes,
      interactive: interactive?(stored, too_large),
      files: stored
    }
  end

  @doc "Whether a usable file is a screenshot (rather than HTML)."
  def screenshot?(name), do: String.starts_with?(Map.get(@types, extension(name), ""), "image/")

  @doc "The board's note naming the ignored files."
  def ignored_note([]), do: nil

  def ignored_note(names),
    do: "Ignored #{Errors.names(names)}: only HTML, screenshots and .zip files are used."

  @doc "The board's note when more files were dropped than are kept."
  def skipped_note(_file_count, 0), do: nil

  def skipped_note(file_count, skipped_count),
    do: "Loaded the first #{file_count} of #{file_count + skipped_count} files."

  # A usable file waits to be read (`load`) until it's known to be kept.
  defp sort_file(%{name: name} = file, {usable, ignored, unreadable}) do
    cond do
      extension(name) == ".zip" ->
        case zip_entries(file) do
          {:ok, entries} -> Enum.reduce(entries, {usable, ignored, unreadable}, &sort_file/2)
          :error -> {usable, ignored, [name | unreadable]}
        end

      Map.has_key?(@types, extension(name)) ->
        {[Map.put_new(file, :load, fn -> {:ok, file.content} end) | usable], ignored, unreadable}

      true ->
        {usable, [name | ignored], unreadable}
    end
  end

  # The archive's files, by their own names (folders dropped), read on demand.
  defp zip_entries(%{content: content}) when is_binary(content) do
    case :zip.list_dir(content) do
      {:ok, [_comment | entries]} ->
        {:ok,
         for {:zip_file, path, info, _comment, offset, compressed_size} <- entries,
             elem(info, 2) == :regular do
           size = elem(info, 1)

           %{
             name: Path.basename(to_string(path)),
             size: size,
             content: nil,
             load: fn -> ZipEntry.read(content, offset, compressed_size, size) end
           }
         end}

      _error ->
        :error
    end
  end

  defp zip_entries(_not_uploaded), do: :error

  # Interactive: exactly one file was kept, it's HTML, and it links to #
  # anchors or has a script that shows or hides sections.
  defp interactive?([%{type: "text/html", content: html}], []) do
    Regex.match?(~r/href\s*=\s*["']#[^"']/i, html) or
      Regex.match?(~r/<script\b[^>]*>[^<]*(\.hidden\b|style\.display)/is, html)
  end

  defp interactive?(_files, _too_large), do: false

  defp extension(name), do: name |> Path.extname() |> String.downcase()
  defp type(name), do: Map.fetch!(@types, extension(name))
end
