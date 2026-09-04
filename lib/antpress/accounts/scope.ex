defmodule AntPress.Accounts.Scope do
  @moduledoc """
  クライアント側の呼び出し元を表すスコープ。

  **`client` を必ず持つ。** antpress のクライアント配下のデータ
  （記事・カテゴリ・画像・問い合わせ）は全て `client_id` でスコープするため、
  スコープがクライアントを運ばないと毎回引き直すことになる。

  ユーザーは必ず 1 つのクライアントに属する（`users.client_id` は NOT NULL）
  ので、ユーザーが決まればクライアントも一意に決まる。
  """
  alias AntPress.Accounts.User

  defstruct user: nil, client: nil

  @doc """
  ユーザーからスコープを作る。**クライアントを preload しておく必要がある。**

  `nil` を渡すと `nil` を返す。
  """
  def for_user(%User{client: %AntPress.Platform.Client{} = client} = user) do
    %__MODULE__{user: user, client: client}
  end

  def for_user(%User{} = user) do
    raise ArgumentError, """
    AntPress.Accounts.Scope.for_user/1 には client を preload したユーザーを渡してください。

    受け取ったユーザー: #{inspect(user.id)}

    スコープはクライアントを運ぶ必要があります（クライアント配下のデータは
    全て client_id でスコープするため）。Accounts 側の取得関数で
    preload: :client を付けてください。
    """
  end

  def for_user(nil), do: nil
end
