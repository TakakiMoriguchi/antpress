# CLAUDE.md

antpress の開発でこのリポジトリを扱うときの指示。

## 最初に読むもの

| 順 | ファイル | 内容 |
| --- | --- | --- |
| 1 | **`docs/DECISIONS.md`** | **決定事項。実装前に必ず読む。** 撤回した判断も理由付きで残してある |
| 2 | `docs/DATA-MODEL.md` | 11 テーブルの定義、索引、運用上の設計判断、実装順序 |
| 3 | `docs/SCREENS.md` | 24 画面、URL 空間、権限 |
| 4 | `AGENTS.md` | **Phoenix / Elixir / LiveView の作法**（Phoenix 生成）。フレームワークの書き方はこちら |

**`CLAUDE.md` はプロジェクト固有のルールのみを扱う。** フレームワークの一般論は
`AGENTS.md` にあるので重複させない。

## 何を作っているか

小規模 HP 向けのマルチテナント型ヘッドレス CMS。**3 階層**。

```
admin（運営者）                      developers.role = admin
  └─ developer（HP 制作エンジニア）   developers.role = developer
       └─ client（店舗・企業）        clients
            └─ users                 users.role = owner | staff
```

コンテンツは配信 API 経由で、別途構築された HP（Astro / React）から取得される。
**HP 自体は antpress の対象外。**

---

## ⚠️ 最重要：テナントスコープは 2 段

**ここが漏れると developer が他社の商売の中身を見られる。** 最も注意すべき箇所。

```elixir
# ✅ developer は自分のクライアントしか触れない。admin だけが越えられる
def get_client!(%Developer{role: :admin}, id), do: Repo.get!(Client, id)
def get_client!(%Developer{id: dev_id}, id) do
  Client |> where(developer_id: ^dev_id) |> Repo.get!(id)
end

# ✅ クライアント配下は必ず client_id で絞る
def list_articles(client_id), do: Article |> where(client_id: ^client_id) |> Repo.all()

# ❌ スコープなしのクエリを書かない
def list_articles, do: Repo.all(Article)
```

- 分離は**アプリケーション層で強制する**。Supabase RLS は使わない
- コンテキスト関数は必ずスコープの起点（`client_id` または `%Developer{}`）を引数に取る

## ⚠️ 2 種類の API キーを混同しない

| キー | 保存方法 | 理由 |
| --- | --- | --- |
| `api_keys.key_hash`（antpress の配信キー） | **ハッシュ（SHA-256）** | 検証だけなので不可逆でよい。毎リクエスト検証するため bcrypt は使わない |
| `developers.anthropic_api_key` | **暗号化（`cloak_ecto` / AES-GCM）** | Claude API を叩くのに**平文が必要**。ハッシュにできない |

- Anthropic キーは**ログ出力禁止**。管理画面では末尾数文字のみ表示
- 暗号鍵は環境変数から読む。DB に置かない

---

## 実装しないもの（「親切に」追加しないこと）

以下は**検討の上で不採用**にした。追加を提案しないこと。理由は `docs/DECISIONS.md` にある。

| 不採用 | 理由の要約 |
| --- | --- |
| **タグ** | 小規模サイトではタグページが thin content になり SEO にマイナス。表記が分裂する |
| **下書きプレビュー** | HP 側に確認用ルートを要求し、責務の境界に反する |
| **メニュー / 店舗情報管理** | 機能スコープ外。HP 側の静的コンテンツで対応 |
| **Stripe / 決済** | 対象は知り合いのエンジニア数名。請求は antpress の外で手動 |
| **スキーマのカスタム定義** | 固定スキーマが設計思想の核心 |
| **表示テーマ / ページビルダー** | スコープ外 |
| **EC** | 将来検討。今のデータモデルを EC 前提で複雑にしない |
| **ダッシュボード / 収益画面** | 表示する指標がなく画面が増えるだけ |

---

## ローカル開発環境

ツールのバージョンは `mise.toml` で固定（Erlang 28 / Elixir 1.20 / Node 24）。
コマンドは `mise exec -- mix ...` で実行する。

```sh
docker compose up -d   # PostgreSQL 17（ポート 5433）
mix ecto.create
mix phx.server         # http://localhost:4001
```

### ⚠️ このマシン固有のポート事情

**既定値のままでは動かない。** 他プロジェクトと衝突するため以下にずらしてある。

| 用途 | ポート | 衝突相手 |
| --- | --- | --- |
| PostgreSQL（dev） | **5433** | 5432 は `viajero` プロジェクトの pgvector が使用中 |
| Phoenix（dev） | **4001** | 4000 は別アプリ（JapanTicket PRESTIGE Manager）が使用中 |
| Phoenix（test） | 4002 | — |

### ⚠️ 設定ファイルを触ったらサーバーを再起動する

`config/*.exs` を編集すると、コードリローダーは**リロードでは対応できず**
ブラウザに `could not compile application: antpress` を出して止まる。

**`mix format` が設定ファイルを整形するだけでも起きる。** 順序に注意:

```sh
# ✅ 正しい順序
mix format && mix compile && mix phx.server

# ❌ サーバー起動後に mix format すると config/*.exs が整形されて止まる
```

### ⚠️ 開発サーバーのポートは `dev.exs` では変えられない

`config/runtime.exs` に**環境ガードなし**のポート設定があり、`dev.exs` より
**後に読まれるため上書きする。**

```elixir
# config/runtime.exs — 全環境に適用される
config :antpress, AntPressWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4001"))]
```

`config` はキーワードリストをマージするので、`dev.exs` の `ip` は残るが
**`port` だけが差し替わる。** ポートを変えるなら **`runtime.exs` を直す。**

### ⚠️ `docker-compose.yml` の `name: antpress` を消さないこと

このディレクトリ名は `app` という汎用的な名前なので、`name` を省略すると
Compose のプロジェクト名が `app` になり、**無関係な別プロジェクトのコンテナ
（18 ヶ月前の `django_app` など）を掴んで再作成・削除しようとする。**

コンテナ名も `antpress-dev-db` にしている。`antpress-db` は
`/Users/tk2/Documents/antpress/api/` の別プロジェクトが使用中のため。

## 新しいファイルをどこに置くか

### 2 つの境界

```
境界 1  lib/antpress/  ⟷  lib/antpress_web/     Phoenix の中核原則
境界 2  コンテキスト分割（Platform / Tenancy / Accounts / Blog）
```

**依存は一方通行。** `lib/antpress/` の中に `Plug` / `conn` / HTML が出てきたら設計違反。
配信 API と管理画面が同じコンテキストを呼ぶので、この分離に実利がある。

**コンテキストの公開 API を通す。** `AntPressWeb` が `AntPress.Platform.Developer` を
直接 `Repo.get` するのは違反。`AntPress.Platform.get_developer!/1` を呼ぶ。
この壁があるから 2 段テナントスコープを 1 箇所で強制できる。

### 判断は 3 つの問いで決まる

```
1. Web を知る必要があるか？
      YES → lib/antpress_web/     NO → lib/antpress/

2. （lib/antpress/ なら）どのドメインか？
      developer → platform/    client → tenancy/
      user      → accounts/    記事    → blog/

3. （lib/antpress_web/ なら）状態を持つ画面か？
      YES → live/              NO → controllers/
```

`controllers/` を使うのは **Cookie を書く必要があるもの**（LiveView は WebSocket 上で
動くため Cookie を書けない）と **JSON API**。それ以外は `live/`。

### 独自 namespace（`lib/antpress_batch` など）は切らない

`_web` は Phoenix 1.2 以前に**別の OTP アプリケーションだった名残**で、
「配信手段ごとに namespace を作る」パターンではない。独立の基準は
**独自の依存を持つ大きな塊かどうか**。

antpress で必要なインターフェース層は 3 つだけ。

| 層 | トリガー | 置き場所 |
| --- | --- | --- |
| HTTP | ブラウザ・API クライアント | `lib/antpress_web/` |
| スケジュール実行 | **時刻** | ドメイン内（例: `blog/webhook_notifier.ex`）。ロジックはドメインそのもので、GenServer は薄い引き金 |
| CLI | 人間・CI | `lib/mix/tasks/` |

⚠️ **外部サービスからの通知は多くが HTTP。** Resend の配信結果通知も
GitHub の push 通知も受け口は `_web`。「Webhook」の名前に引きずられて
別の層を作らない。

### 画面固有の JS は LiveView の隣に置く

Phoenix 1.8 の **colocated hooks** を使う。`assets/js/` に別ファイルを作らない。

```heex
<div id="editor" phx-hook=".ToastEditor" phx-update="ignore"></div>
<script :type={Phoenix.LiveView.ColocatedHook} name=".ToastEditor">
  export default { mounted() { /* ... */ } }
</script>
```

- **フック名は `.` 始まり必須**
- コンパイル時に自動で `app.js` バンドルへ統合される
- `assets/` はビルドツールのエントリポイント専用（`app.css` / `app.js` / `vendor/`）

## 規約

### 命名

- ブログ領域のテーブルは **`blog_` 接頭辞**: `blog_articles`, `blog_categories`
- コンテキスト構成（3 階層モデルの各層に対応）:

  | コンテキスト | 扱うもの |
  | --- | --- |
  | `AntPress.Platform` | `developers`（admin / developer） |
  | `AntPress.Tenancy` | `clients`（テナント） |
  | `AntPress.Accounts` | `users`（owner / staff） |
  | `AntPress.Blog` | `blog_articles`, `blog_categories` |
  | （将来）`AntPress.Commerce` | EC |
- 外部キー列は `article_id`（`blog_article_id` にしない。Ecto の慣例に従う）
- 主キーは**全テーブル UUID**（`--binary-id` で生成済み）
- スラッグの一意制約は **`UNIQUE (client_id, slug)`**。グローバル一意にしない

### 配信 API

- 認証は `Authorization: Bearer` の 1 種類のみ。**認証なしのアクセスは全て拒否**
- **CORS は一切許可しない。** ブラウザからの直接アクセスを構造的に不可能にする
- **公開済み記事のみ返す**: `status = :published AND published_at <= now()`
- キーから `client_id` を解決する。リクエストのパラメータを信用しない
- `clients.status` と **`developers.status` の両方**を確認する（停止判定）
- 停止時の `403` には**停止理由が分かるメッセージ**を含める
- エンドポイントのパスは `/api/v1/articles`（テーブル名と揃えない）
- OpenAPI は `open_api_spex` でコードから生成する

### 記事の公開と Webhook

- 予約投稿に専用ステータスを作らない。`status = :published` ＋ 未来の `published_at`
- Webhook は **`published_notified_at IS NULL` を拾う方式**。これ自体がリトライ機構
- **Oban は入れない。** `GenServer` ＋ `Process.send_after/3` で足りる

### AI 生成

- モデルは **`claude-sonnet-5`**
- API キーは **developer の BYOK**（`developers.anthropic_api_key`）
- Anthropic キー未登録の developer は、クライアントを AI プランに設定できない
- 非同期。`blog_articles.generation_status` で状態管理し、LiveView にストリーミング
- **再生成の履歴は残さない**（上書き）
- 起動時に、一定時間以上 `:generating` のままのレコードを `:failed` に戻す

### エディタ

- 基本プランは **Toast UI Editor**（Markdown / WYSIWYG 切替）
- ⚠️ **`phx-update="ignore"` を必ず付ける。** 付けないと LiveView の DOM パッチで
  JS が構築したエディタが破壊される
- AI プランは自前実装。TipTap 等の大きな JS エコシステムは使わない

### お問い合わせ

- **DB 保存を先に行い、その後メール送信する。** 送信失敗で問い合わせを失わないため
- 転送先は `clients.contact_notification_email`
- フォーム項目は `hidden / optional / required` の enum。
  boolean 2 つにしない（「非表示かつ必須」を型で排除している）

### 認証

`mix phx.gen.auth`（Phoenix 1.8）の生成コードを使う。**マジックリンク優先、パスワードは任意。**

- **セルフサインアップは実装しない。** 生成された `/developers/register` は削除済み。
  復活させないこと。作成経路は seed（最初の admin）と admin 発行のみ
- ⚠️ **パスワードを設定するなら `confirmed_at` も必ず入れる。**
  「未確認かつパスワード設定済み」はマジックリンクログインが `raise` する
- `--assign-key` で分けているので、レイアウトの attr は
  `current_developer`（将来 `current_user` も追加）。`current_scope` ではない
- パスワードハッシュは **bcrypt**（argon2 は Fly.io の小インスタンスに重い）

```sh
# 最初の admin を作る
ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=... mix run priv/repo/seeds.exs
```

### 言語

- ドキュメント・UI・コミットメッセージは**日本語**
