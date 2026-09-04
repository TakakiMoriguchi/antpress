defmodule AntPress.Media.ProbeTest do
  use ExUnit.Case, async: true

  import AntPress.MediaFixtures

  alias AntPress.Media.Probe

  describe "format/1" do
    test "対応する 4 形式を判別する" do
      assert Probe.format(png()) == :png
      assert Probe.format(gif()) == :gif
      assert Probe.format(jpeg()) == :jpeg
      assert Probe.format(webp()) == :webp
    end

    test "GIF87a も GIF として扱う" do
      assert Probe.format(<<"GIF87a", 1::little-16, 1::little-16>>) == :gif
    end

    test "SVG は対応形式に含めない" do
      # スクリプトを埋め込めるため。同一オリジンで配信すると XSS になる
      assert Probe.format(svg()) == nil
    end

    test "画像でないものは nil" do
      assert Probe.format(not_an_image()) == nil
      assert Probe.format("") == nil
    end

    test "拡張子を偽装しても中身で判定される" do
      # 「.png」という名前の HTML を上げられても content_type は決まらない
      assert Probe.content_type("<!DOCTYPE html><html></html>") == nil
    end
  end

  describe "content_type/1" do
    test "MIME タイプを返す" do
      assert Probe.content_type(png()) == "image/png"
      assert Probe.content_type(gif()) == "image/gif"
      assert Probe.content_type(jpeg()) == "image/jpeg"
      assert Probe.content_type(webp()) == "image/webp"
    end

    test "判別できなければ nil" do
      assert Probe.content_type(not_an_image()) == nil
      assert Probe.content_type(:not_a_binary) == nil
    end
  end

  describe "size/1" do
    test "PNG の IHDR から読む" do
      assert Probe.size(png(1200, 630)) == {1200, 630}
    end

    test "GIF の論理画面サイズから読む" do
      assert Probe.size(gif(320, 240)) == {320, 240}
    end

    test "JPEG は SOF セグメントを探して読む" do
      # APP0 を読み飛ばした先に SOF0 がある形
      assert Probe.size(jpeg(640, 480)) == {640, 480}
    end

    test "WebP 可逆（VP8L）は 14 ビットずつパックされた値を読む" do
      assert Probe.size(webp(200, 100)) == {200, 100}
    end

    test "WebP 非可逆（VP8）を読む" do
      body =
        <<"RIFF", 0::little-32, "WEBP", "VP8 ", 0::little-32, 0::24, 0x9D, 0x01, 0x2A,
          1024::little-16, 768::little-16>>

      assert Probe.size(body) == {1024, 768}
    end

    test "WebP 拡張（VP8X）はキャンバスサイズが実寸 - 1 で入っている" do
      body =
        <<"RIFF", 0::little-32, "WEBP", "VP8X", 10::little-32, 0::32, 1919::little-24,
          1079::little-24>>

      assert Probe.size(body) == {1920, 1080}
    end

    test "読めない場合は nil。**アップロード失敗にはしない**" do
      assert Probe.size(not_an_image()) == nil
      # ヘッダが途中で切れているケース
      assert Probe.size(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>) == nil
      assert Probe.size(<<0xFF, 0xD8, 0xFF, 0xE0, 16::16>>) == nil
    end

    test "SOS 以降は走査しない" do
      # SOF が無いまま圧縮データが始まる壊れた JPEG
      assert Probe.size(<<0xFF, 0xD8, 0xFF, 0xDA, 0::64>>) == nil
    end
  end
end
