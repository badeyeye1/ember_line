defmodule EmberLine.Modeling.Intake.ZipEntry do
  @moduledoc """
  Reads one entry of a .zip held in memory, never producing more bytes than
  the archive declares for it. An archive can lie about an entry's size (a
  "zip bomb"), so the entry is inflated a chunk at a time and given up on as
  soon as it passes its declared size, instead of being unpacked whole.
  """

  import Bitwise, only: [band: 2]

  @local_header 0x04034B50
  @stored 0
  @deflated 8
  @encrypted 0x1

  @doc """
  The entry whose local header starts at `offset`, holding `compressed_size`
  bytes that unpack to `size`. `:error` when it's encrypted, uses another
  method, is cut short, or unpacks to more or fewer than `size` bytes.
  """
  @spec read(binary(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, binary()} | :error
  def read(zip, offset, compressed_size, size) do
    with <<_skip::binary-size(^offset), rest::binary>> <- zip,
         <<@local_header::little-32, _version::16, flags::little-16, method::little-16, _time::32,
           _crc::32, _csize::32, _usize::32, name_len::little-16, extra_len::little-16,
           rest::binary>> <- rest,
         0 <- band(flags, @encrypted),
         <<_name_extra::binary-size(^name_len + ^extra_len), data::binary-size(^compressed_size),
           _after::binary>> <- rest do
      unpack(method, data, size)
    else
      _bad -> :error
    end
  end

  defp unpack(@stored, data, size) when byte_size(data) == size, do: {:ok, data}
  defp unpack(@deflated, data, size), do: inflate(data, size)
  defp unpack(_method, _data, _size), do: :error

  defp inflate(data, size) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, -15)
      z |> :zlib.safeInflate(data) |> collect(z, size, [], 0)
    rescue
      _bad_data -> :error
    after
      :zlib.close(z)
    end
  end

  # safeInflate hands back a bounded chunk at a time; stop once past `size`.
  defp collect({state, out}, z, size, acc, bytes) do
    bytes = bytes + IO.iodata_length(out)
    acc = [acc | out]

    case state do
      _any when bytes > size -> :error
      :continue -> z |> :zlib.safeInflate([]) |> collect(z, size, acc, bytes)
      :finished when bytes == size -> {:ok, IO.iodata_to_binary(acc)}
      :finished -> :error
    end
  end
end
