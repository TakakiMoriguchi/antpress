defmodule AntPress.Storage.FailingStub do
  @moduledoc """
  必ず失敗するストレージアダプタ。**テスト専用。**

  ストレージが落ちているときに `AntPress.Media` がどう振る舞うかを検証する。
  実際に Supabase を落とすことはできないため。
  """
  @behaviour AntPress.Storage

  @impl true
  def put(_path, _body, _content_type), do: {:error, :stub_failure}

  @impl true
  def delete(_path), do: {:error, :stub_failure}

  @impl true
  def public_url(path), do: "/stub/" <> path
end
