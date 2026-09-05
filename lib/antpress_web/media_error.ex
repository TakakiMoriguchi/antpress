defmodule AntPressWeb.MediaError do
  @moduledoc """
  `AntPress.Media.create_image/2` のエラーを画面用の 1 文に直す。

  画像のアップロード口が 3 つある（画像管理・記事フォームのサムネイル選択・
  エディタ本文への挿入）ので、**同じ文言を 3 箇所に書かない**ためにまとめている。

  ⚠️ `lib/antpress/` 側には置かない。`translate_error/1`（gettext）を使うため。
  """
  import AntPressWeb.CoreComponents, only: [translate_error: 1]

  @doc """
  エラーを日本語の 1 文にする。

      {:error, :unsupported_format}   → "対応していない画像形式です（…）"
      {:error, {:storage, _reason}}   → "保存先への書き込みに失敗しました…"
      {:error, %Ecto.Changeset{}}     → changeset のエラーを畳んだもの
  """
  def message(:unsupported_format),
    do: "対応していない画像形式です（JPEG / PNG / GIF / WebP）"

  def message({:storage, _reason}),
    do: "保存先への書き込みに失敗しました。しばらくしてからもう一度お試しください"

  def message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} -> translate_error({msg, opts}) end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> Enum.join("。")
    |> case do
      "" -> "保存できませんでした"
      message -> message
    end
  end

  def message(other), do: "保存できませんでした（#{inspect(other)}）"
end
