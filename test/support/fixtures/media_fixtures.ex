defmodule AntPress.MediaFixtures do
  @moduledoc """
  `AntPress.Media` のテスト用ヘルパ。

  画像バイナリは**ヘッダだけを手で組む**。実ファイルを
  `test/support/fixtures/` に置かないのは、`AntPress.Media.Probe` が
  読むのが先頭数十バイトだけで、それ以上のデータに意味がないため。
  縦横サイズを引数で変えられる方がテストが書きやすい。
  """

  import Bitwise

  @doc "PNG のヘッダ（IHDR まで）"
  def png(width \\ 800, height \\ 600) do
    <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 13::32, "IHDR", width::32, height::32>>
  end

  @doc "GIF89a のヘッダ"
  def gif(width \\ 320, height \\ 240) do
    <<"GIF89a", width::little-16, height::little-16>>
  end

  @doc "JPEG（APP0 セグメントを挟んで SOF0 を置く）"
  def jpeg(width \\ 640, height \\ 480) do
    <<0xFF, 0xD8, 0xFF, 0xE0, 16::16, 0::112, 0xFF, 0xC0, 17::16, 8, height::16, width::16>>
  end

  @doc "WebP 可逆（VP8L）"
  def webp(width \\ 200, height \\ 100) do
    bits = width - 1 + ((height - 1) <<< 14)
    <<"RIFF", 0::little-32, "WEBP", "VP8L", 0::little-32, 0x2F, bits::little-32>>
  end

  @doc "画像として判別できないバイナリ"
  def not_an_image, do: "これは画像ではありません"

  @doc "SVG。対応形式に含めていない（XSS を避けるため）"
  def svg, do: "<svg><script>alert(1)</script></svg>"

  @doc """
  画像を 1 件作る。

  `body` を渡さなければ PNG になる。サイズを変えたい場合は
  `png(1200, 800)` などを渡す。
  """
  def image_fixture(scope, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{filename: "sample.png", body: png()})

    {:ok, image} = AntPress.Media.create_image(scope, attrs)
    image
  end
end
