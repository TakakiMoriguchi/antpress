defmodule AntPressWeb.JSTTest do
  @moduledoc """
  管理画面の日時を日本時間で扱う変換。

  ⚠️ ここが壊れると**予約投稿が 9 時間ずれる。**
  """
  use ExUnit.Case, async: true

  alias AntPressWeb.JST

  describe "format/1" do
    test "UTC を日本時間で表示する" do
      assert JST.format(~U[2026-09-10 09:00:00Z]) == "2026-09-10 18:00"
    end

    test "日をまたぐ" do
      assert JST.format(~U[2026-09-10 20:00:00Z]) == "2026-09-11 05:00"
    end

    test "nil は nil" do
      assert JST.format(nil) == nil
    end
  end

  describe "to_input_value/1" do
    test "datetime-local が読める形式にする" do
      assert JST.to_input_value(~U[2026-09-10 09:00:00Z]) == "2026-09-10T18:00"
    end

    test "⚠️ 文字列はそのまま返す（二重変換を防ぐ）" do
      # 検証エラー後の再描画では、ユーザーが入力したままの文字列
      # （＝すでに日本時間）が来る
      assert JST.to_input_value("2026-09-10T18:00") == "2026-09-10T18:00"
    end

    test "nil は nil" do
      assert JST.to_input_value(nil) == nil
    end
  end

  describe "to_utc_param/1" do
    test "日本時間の入力を UTC に直す" do
      assert JST.to_utc_param("2026-09-10T18:00") == "2026-09-10T09:00:00Z"
    end

    test "秒つきでも扱える" do
      assert JST.to_utc_param("2026-09-10T18:00:30") == "2026-09-10T09:00:30Z"
    end

    test "日をまたいで戻る" do
      assert JST.to_utc_param("2026-09-10T03:00") == "2026-09-09T18:00:00Z"
    end

    test "空はそのまま（未入力を勝手に埋めない）" do
      assert JST.to_utc_param("") == ""
      assert JST.to_utc_param(nil) == nil
    end

    test "解釈できない値はそのまま返す（弾くのは changeset の役目）" do
      assert JST.to_utc_param("あ") == "あ"
      assert JST.to_utc_param("2026-13-45T99:99") == "2026-13-45T99:99"
    end

    test "往復して元に戻る" do
      utc = ~U[2026-09-10 09:00:00Z]

      assert utc
             |> JST.to_input_value()
             |> JST.to_utc_param()
             |> then(&elem(DateTime.from_iso8601(&1), 1)) == utc
    end
  end

  describe "shift_params/2" do
    test "指定したキーだけ変換する" do
      params = %{"title" => "題", "published_at" => "2026-09-10T18:00"}

      assert JST.shift_params(params, ["published_at"]) == %{
               "title" => "題",
               "published_at" => "2026-09-10T09:00:00Z"
             }
    end

    test "⚠️ 送られてこなかったキーを勝手に作らない" do
      # Map.update/4 だと既定値でキーができてしまい、
      # 「未入力」が「空文字を送った」に変わる
      assert JST.shift_params(%{"title" => "題"}, ["published_at"]) == %{"title" => "題"}
    end
  end
end
