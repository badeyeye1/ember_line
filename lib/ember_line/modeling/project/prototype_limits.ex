defmodule EmberLine.Modeling.Project.PrototypeLimits do
  @moduledoc """
  load-prototype's limits, shared by the aggregate and the code that reads
  the files: up to 80 files are kept, the first 80 by name; a kept file may
  be up to 20 MB, and the kept files up to 100 MB together.
  """

  @max_files 80
  @mb 1024 * 1024

  def max_files, do: @max_files
  def max_file_bytes, do: 20 * @mb
  def max_total_bytes, do: 100 * @mb

  @doc "The usable names that are kept (the first 80 by name) and how many are skipped."
  @spec kept([String.t()]) :: {[String.t()], non_neg_integer()}
  def kept(names) do
    sorted = Enum.sort(names)
    {Enum.take(sorted, @max_files), max(length(sorted) - @max_files, 0)}
  end
end
