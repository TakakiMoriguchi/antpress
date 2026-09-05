defmodule AntPressWeb.JST do
  @moduledoc """
  管理画面の日時を**日本時間**で表示・入力するための変換。

  ## なぜ必要か

  `blog_articles.published_at` は UTC で保存する（正しい）。しかし画面に
  そのまま出すと**日本のユーザーには 9 時間ずれた時刻が見える。**

  さらに `<input type="datetime-local">` はタイムゾーンを持たないので、
  「2026-09-10 18:00」と入力された値をそのまま UTC として保存すると
  **日本時間の翌日 03:00 に公開される。** 予約投稿が実質壊れる
  （実際にそうなっていた）。

  ## ⚠️ 固定オフセット（+9:00）で扱う。タイムゾーンデータベースは入れない

  * 対象は日本国内の店舗・企業のみ（→ `docs/DECISIONS.md` 1.1）
  * **日本には夏時間が無い**ので、オフセットは通年 +9:00 で変わらない
  * `tzdata` / `tz` は実行時にデータ更新を行う可動部が増える。
    得られるものが無いのに Fly.io 上の依存を増やしたくない

  海外のクライアントを扱う必要が出たら、そのときにタイムゾーンを
  クライアントごとに持たせる（`clients.time_zone`）判断をする。

  ## ⚠️ 配信 API はここを通さない

  API は UTC の ISO8601 をそのまま返す。表示形式は HP 側の責務。
  ここは**管理画面だけ**の変換。
  """

  # 日本標準時。夏時間が無いので固定値でよい
  @offset_seconds 9 * 3600

  @doc "UTC の DateTime を日本時間に直す"
  def to_jst(%DateTime{} = utc), do: DateTime.add(utc, @offset_seconds, :second)

  @doc """
  画面表示用の文字列（日本時間）。

      iex> AntPressWeb.JST.format(~U[2026-09-10 09:00:00Z])
      "2026-09-10 18:00"
  """
  def format(nil), do: nil

  def format(%DateTime{} = utc) do
    utc |> to_jst() |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  @doc """
  `<input type="datetime-local">` に入れる値（日本時間）。

  ⚠️ 検証エラー後の再描画では、changeset の値が**ユーザーが入力した
  ままの文字列**（＝すでに日本時間）になる。二重に変換しないよう
  そのまま返す。
  """
  def to_input_value(nil), do: nil

  def to_input_value(%DateTime{} = utc) do
    utc |> to_jst() |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  def to_input_value(value), do: value

  @doc """
  `<input type="datetime-local">` から来た値（日本時間）を UTC の
  ISO8601 に直す。changeset に渡す前に通す。

  解釈できない値はそのまま返す。**弾くのは changeset の役目**で、
  ここで落とすと検証エラーが出せない。

      iex> AntPressWeb.JST.to_utc_param("2026-09-10T18:00")
      "2026-09-10T09:00:00Z"
  """
  def to_utc_param(value) when value in [nil, ""], do: value

  def to_utc_param(value) when is_binary(value) do
    case parse_local(value) do
      {:ok, naive} ->
        naive
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.add(-@offset_seconds, :second)
        |> DateTime.to_iso8601()

      :error ->
        value
    end
  end

  def to_utc_param(value), do: value

  @doc """
  フォームの params に含まれる日時を UTC に直す。

      params |> AntPressWeb.JST.shift_params(["published_at"])
  """
  def shift_params(params, keys) when is_map(params) do
    Enum.reduce(keys, params, fn key, acc ->
      # ⚠️ Map.update/4 は既定値でキーを**作ってしまう**。
      # 送られてこなかった項目を勝手に追加しない
      if Map.has_key?(acc, key) do
        Map.put(acc, key, to_utc_param(acc[key]))
      else
        acc
      end
    end)
  end

  # datetime-local は秒を送らないことがある（"2026-09-10T18:00"）
  defp parse_local(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} ->
        {:ok, naive}

      _ ->
        case NaiveDateTime.from_iso8601(value <> ":00") do
          {:ok, naive} -> {:ok, naive}
          _ -> :error
        end
    end
  end
end
