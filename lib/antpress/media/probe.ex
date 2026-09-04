defmodule AntPress.Media.Probe do
  @moduledoc """
  画像バイナリのヘッダを覗いて**形式**と**縦横サイズ**を得る。
  PNG / JPEG / GIF / WebP に対応。

  ## なぜ依存を足さずに自前で読むか

  必要なのは**先頭数十バイトの解釈だけ**で、デコードもリサイズもしない。
  ImageMagick / libvips のバインディングを入れるとネイティブ依存が増え、
  Fly.io のイメージが重くなる。薄く保つ方針（→ `CLAUDE.md`）に合わない。

  ## なぜサーバー側で読むか

  ブラウザは MIME タイプもサイズも申告してくるが、**申告は信用しない**。
  配信 API がリクエストのパラメータを信用しないのと同じ姿勢
  （→ `CLAUDE.md`）。ファイル名の拡張子も同様に使わない。
  縦横サイズは配信 API が返し、HP 側が `<img width height>` に使う
  （**レイアウトシフト（CLS）を防ぐ** = SEO に効く）ため、正しさが要る。

  読めない形式や壊れたヘッダでは `nil` を返す。`images.width` / `height` は
  null 許容なので、**サイズが読めないことをアップロード失敗にはしない**。
  """

  import Bitwise

  @doc """
  `{width, height}` を返す。判別できなければ `nil`。

      iex> AntPress.Media.Probe.size(png_binary)
      {800, 600}
  """
  def size(binary) when is_binary(binary), do: parse(binary)
  def size(_), do: nil

  @doc """
  画像形式を返す。判別できなければ `nil`。

  **ブラウザが申告した MIME タイプの代わりに使う。**
  `image/png` と偽って別のファイルを上げられても、ここで弾ける。
  """
  def format(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: :png
  def format(<<"GIF87a", _::binary>>), do: :gif
  def format(<<"GIF89a", _::binary>>), do: :gif
  def format(<<0xFF, 0xD8, 0xFF, _::binary>>), do: :jpeg
  def format(<<"RIFF", _size::little-32, "WEBP", _::binary>>), do: :webp
  def format(_), do: nil

  @doc """
  バイナリから判定した MIME タイプ。判別できなければ `nil`。
  """
  def content_type(binary) when is_binary(binary) do
    case format(binary) do
      :png -> "image/png"
      :gif -> "image/gif"
      :jpeg -> "image/jpeg"
      :webp -> "image/webp"
      nil -> nil
    end
  end

  def content_type(_), do: nil

  # ── PNG ── IHDR は必ず先頭チャンク
  defp parse(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _len::32, "IHDR", w::32, h::32, _::binary>>),
    do: {w, h}

  # ── GIF ── 論理画面サイズ（リトルエンディアン）
  defp parse(<<"GIF", _ver::binary-size(3), w::little-16, h::little-16, _::binary>>), do: {w, h}

  # ── WebP ── RIFF コンテナの中の最初のチャンクで形式が分かれる
  defp parse(<<"RIFF", _size::little-32, "WEBP", rest::binary>>), do: webp(rest)

  # ── JPEG ── SOF セグメントを探して走査する
  defp parse(<<0xFF, 0xD8, rest::binary>>), do: jpeg(rest)

  defp parse(_), do: nil

  # WebP 拡張形式。キャンバスサイズは「実寸 - 1」で入っている
  defp webp(
         <<"VP8X", _size::little-32, _flags_and_reserved::32, w::little-24, h::little-24,
           _::binary>>
       ),
       do: {w + 1, h + 1}

  # WebP 非可逆。フレームタグ 3 バイトの後に start code が入る
  defp webp(
         <<"VP8 ", _size::little-32, _frame_tag::24, 0x9D, 0x01, 0x2A, w::little-16, h::little-16,
           _::binary>>
       ),
       do: {w &&& 0x3FFF, h &&& 0x3FFF}

  # WebP 可逆。14 ビットずつパックされている
  defp webp(<<"VP8L", _size::little-32, 0x2F, bits::little-32, _::binary>>) do
    {(bits &&& 0x3FFF) + 1, (bits >>> 14 &&& 0x3FFF) + 1}
  end

  defp webp(_), do: nil

  # 詰め物の 0xFF は読み飛ばす
  defp jpeg(<<0xFF, 0xFF, rest::binary>>), do: jpeg(<<0xFF, rest::binary>>)

  # SOF0〜SOF15。ただし 0xC4（DHT）/ 0xC8（JPG）/ 0xCC（DAC）はサイズを持たない
  defp jpeg(<<0xFF, marker, _len::16, _precision::8, h::16, w::16, _::binary>>)
       when marker in 0xC0..0xCF and marker not in [0xC4, 0xC8, 0xCC],
       do: {w, h}

  # SOS 以降は圧縮データ。正しい JPEG なら SOF は必ず手前にあるので打ち切る
  defp jpeg(<<0xFF, 0xDA, _::binary>>), do: nil

  # ペイロードを持たないマーカー
  defp jpeg(<<0xFF, marker, rest::binary>>)
       when marker in [0x01, 0xD8] or marker in 0xD0..0xD7,
       do: jpeg(rest)

  # それ以外は長さぶん読み飛ばす
  defp jpeg(<<0xFF, _marker, len::16, rest::binary>>) when len >= 2 do
    skip = len - 2

    case rest do
      <<_::binary-size(^skip), tail::binary>> -> jpeg(tail)
      _ -> nil
    end
  end

  defp jpeg(_), do: nil
end
