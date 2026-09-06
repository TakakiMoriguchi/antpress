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

## ⚠️ 画像は「公開」、配信 API は「非公開」

**同じ Supabase プロジェクトでも扱いが逆。混同すると片方が壊れる。**

| | 認証 | CORS |
| --- | --- | --- |
| 配信 API `/api/v1/*` | **Bearer 必須** | **全拒否** |
| 画像（Storage の public バケット） | **なし** | ブラウザから直接読める |

画像は HP の `<img src>` から読まれるので、認証を要求すると**記事本文に
埋めた画像が壊れる。** バケットは `antpress`、**Public** で作る。
パスに推測不能な UUID が入るだけで秘匿性はない前提で扱う。

⚠️ **削除しても公開 URL は約 1 時間画像を返し続ける**（Cloudflare の
キャッシュ。実体とレコードは即座に消える）。即時に非公開にする手段はない
前提で扱う。詳細と実測値は `docs/DECISIONS.md` 4.2。

### ストレージは差し替え可能。テストはネットワークに依存させない

`AntPress.Storage`（behaviour）＋ `Local`（dev / test）/ `Supabase`（本番）。

- `SUPABASE_URL` が設定されていれば Supabase、無ければローカルディスク
- **本番は未設定なら起動時に落とす**（Fly.io のディスクは揮発するため、
  設定漏れに気付かないまま画像が消えるのを防ぐ）
- Supabase アダプタのテストは `Req.Test` をプラグで差し込む。
  設定に `:plug` を渡せる穴を空けてある
- 環境変数は `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` /
  `SUPABASE_STORAGE_BUCKET`（→ `.env.example`）

### ⚠️ アップロードされたファイルの申告を信用しない

- **MIME タイプはブラウザの申告を使わない。** バイナリの先頭バイトから
  判定する（`AntPress.Media.Probe`）
- **ファイル名を保存パスに使わない。** パスは
  `clients/{client_id}/{uuid}.{ext}` を antpress 側が組む
- **SVG は対応形式に含めない。** スクリプトを埋め込めるため
- ユーザーが編集できるのは `alt_text` だけ。changeset を
  `create_changeset/3` と `alt_text_changeset/2` に分けてある

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
| **クライアントの削除** | 子テーブル 4 つが `on_delete: :delete_all`。1 操作で記事・画像・アカウント・問い合わせが全部消える。契約終了は `status = :suspended` |
| **記事アドレスの手入力・編集** | URL 内の語は SEO にほぼ効かない。公開後の変更は既存リンクを 404 にする。システム生成で固定する |
| **画像のリサイズ / サムネイル生成** | HP は Astro なので `<Image>` がビルド時に最適化できる。配信側で作ると同じ処理が 2 箇所に存在する |

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

### ⚠️ テスト DB に対して `Sandbox.mode(:auto)` でスクリプトを走らせない

`MIX_ENV=test mix run -e '...'` で `Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)`
を使うと、**書き込みがサンドボックスのトランザクション外で commit され、
ロールバックされずに残る。**

生成テストには `Repo.update_all(UserToken, set: [...])` のように
**WHERE 句なしで全行を対象にして `{1, nil}` を期待する**ものがあるため、
残骸が 1 行あるだけでテストが落ちる。原因が分かりにくい。

調査で一時的にデータを作る必要がある場合:

```sh
# 開発 DB を使う（テスト DB を触らない）
mix run -e '...'

# それでもテスト DB を汚したら作り直す
MIX_ENV=test mix ecto.drop && MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate
```

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
境界 2  コンテキスト分割（Platform / Accounts / Blog）
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
      developer / client / api_key → platform/
      user（owner / staff）        → accounts/
      記事・カテゴリ               → blog/
      画像                         → media/
      外部サービスの口（インフラ）   → 直下（storage.ex / mailer.ex / vault.ex）

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
  | `AntPress.Platform` | `developers`, `clients`, `api_keys`（運営・再販の管理領域） |
  | `AntPress.Accounts` | `users`（owner / staff） |
  | `AntPress.Blog` | `blog_articles`, `blog_categories` |
  | `AntPress.Media` | `images`（クライアントの素材置き場） |
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
- **画像の説明（`images.alt_text`）の自動生成もここで扱う。**
  基本プランでは店舗オーナーがまず埋めない項目なので、AI プランで
  埋まるようにして初めて価値が出る（→ `docs/DECISIONS.md` 3.3）
- API キーは **developer の BYOK**（`developers.anthropic_api_key`）
- Anthropic キー未登録の developer は、クライアントを AI プランに設定できない
- 非同期。`blog_articles.generation_status` で状態管理し、LiveView にストリーミング
- **再生成の履歴は残さない**（上書き）
- 起動時に、一定時間以上 `:generating` のままのレコードを `:failed` に戻す

### エディタ

- 基本プランは **Toast UI Editor**（Markdown / WYSIWYG 切替）。ライセンスは MIT
- ⚠️ **`phx-update="ignore"` を必ず付ける。** 付けないと LiveView の DOM パッチで
  JS が構築したエディタが破壊される
- ⚠️ **本文の hidden input も `ignore` の中に置く。** 外に置くと、他フィールドの
  検証で再描画されたときに JS が入れた本文がサーバー側の古い値へ巻き戻る
- ⚠️ **`addImageBlobHook` を必ず渡す。** 渡さないと画像が data URI として
  本文に埋め込まれ、記事と配信 API のレスポンスが肥大する。
  送り先は `POST /client/editor/images`
- ⚠️ **npm の dist は使えない**（prosemirror が同梱されていない）。
  自己完結しているのは CDN の `toastui-editor-all.min.js` だけ。
  `priv/static/vendor/` に同梱し、記事フォームだけが `<script>` で読む
  （→ `docs/VENDORED-ASSETS.md`）
- AI プランは自前実装。TipTap 等の大きな JS エコシステムは使わない

### ⚠️ 記事のアドレス（`slug`）はシステムが決める

作成時にランダムな 13 文字を割り当て、**以後変更できない。**
`Article.changeset/3` は `slug` を cast しない。画面に入力欄も出さない。

**URL 内の語は SEO にほぼ効かない**一方、公開後に URL が変わると既存の
リンクが 404 になり、蓄積された評価も失われる。HP は SSG なので
リダイレクトも張れない。**編集できなければこの事故は構造的に起きない。**

「親切に」入力欄を戻さないこと（→ `docs/DECISIONS.md` 3.2）。

### ⚠️ 日時は UTC で保存し、管理画面では日本時間で見せる

`published_at` は UTC で保存する。**画面にそのまま出すと 9 時間ずれる。**

さらに `<input type="datetime-local">` はタイムゾーンを持たないので、
「18:00」と入力された値をそのまま UTC として保存すると**日本時間の
翌日 03:00 に公開される。予約投稿が実質壊れる**（実際にそうなっていた）。

変換は `AntPressWeb.JST` に集約してある。表示は `format/1`、
入力欄は `to_input_value/1`、保存前は `shift_params/2`。

- **固定オフセット +9:00。** 日本には夏時間が無く、対象も日本国内のみ。
  `tzdata` / `tz` は実行時にデータ更新を行う可動部が増えるので入れない
- ⚠️ **配信 API はここを通さない。** UTC の ISO8601 をそのまま返す。
  表示形式は HP 側の責務

### 記事本文の扱い

- **`body` は常に Markdown。** `body_format` は次に開くエディタのモードの記録
- **`body_html` はサーバー側で生成する。** エディタの `getHTML()` は使わない
- **Markdown に書かれた生 HTML は通さない**（`unsafe: false`）。
  `<script>` も `<iframe>` も落ちる。**earmark は使わない**
  （廃止済み ＋ stored XSS の CVE）。MDEx を使う
- ⚠️ `category_id` / `thumbnail_image_id` は**同じクライアントのものか検証する**。
  外部キー制約は「存在するか」しか見ない。
  `AntPress.Blog.validate_scoped_associations/2`

### ⚠️ `priv/static/vendor/` に置いたものは全部公開される

`static_paths/0` に `vendor` を入れているので、その配下は**すべて HTTP で
取得できる**。同梱アセットの出所や更新手順のメモは `docs/` に置く
（README を置いてしまい公開状態になっていた）。

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

### ⚠️ フォーム部品の大きさとラベル

**サイズは `assets/css/app.css` のテーマ変数で決める。個別に付けない。**

| | 値 | 備考 |
| --- | --- | --- |
| `--size-field` | `0.25rem` | 入力欄・選択欄・ボタンの高さ（`× 10` = **40px**）。daisyUI 既定の `0.21875rem` は 35px で小さい |
| 文字サイズ | `1rem`（16px） | daisyUI は iOS 対策で**フォーカス時だけ** 16px に上げる。常時 16px なら跳ねない |

- ⚠️ `input-sm` / `btn-sm` を個別に付けない。揃わなくなる
- ⚠️ **ラベルは `<.field_label>` を使う。daisyUI の `.label` を直接使わない。**
  `.fieldset` の `font-size: 0.75rem` と `.label` の 60% 不透明度が重なって、
  `.input` のラベルだけ極端に小さく薄くなる（実際にそうなっていた）
- 項目の間隔は `.input` の `fieldset mb-5`。手書きの項目も `mb-5` に揃える
- 構造は `test/antpress_web/responsive_test.exs` で固定してある

### ⚠️ レスポンシブ（全ページ対応済み）

client 側だけでなく admin / developer 側も含めて全ページ対応する。
崩れやすい箇所は決まっているので、新しい画面でも同じ形にする。

| 箇所 | やること |
| --- | --- |
| **表** | `.table` コンポーネントを使う（`overflow-x-auto` の囲みが入っている）。生の `<table>` を書くなら自分で囲む |
| **表の列** | 副次的な列は `:col` の `class` に `"hidden sm:table-cell"` を渡して狭い画面で隠す。横スクロールに頼らない |
| **見出し** | `.header` を使う（狭い画面でタイトルとボタンが縦に積まれる） |
| **ナビ** | `Layouts.app` が担当。項目は `nav_items/1` の 1 箇所だけで定義する |
| **横並び** | ボタンや画像を並べるところは `flex-wrap` を付ける |
| **主要ボタン** | `.header` の `<:actions>` に置く。狭い画面で**全幅**になる。左に寄せて積むと幅がばらばらで不格好 |
| **絞り込みタブ** | 狭い画面は `w-full`、各タブは `flex-1 sm:flex-none` で等分にする |
| **入力欄の幅** | `w-full sm:w-64` のように、狭い画面では全幅にする |

- ⚠️ **Tailwind の任意値で `calc` を使うときは演算子をアンダースコアにする**
  （`w-[calc(100vw_-_2rem)]`）。スペースのままだとクラスが生成されない
- ⚠️ **`.header` の `<:actions>` に `items-start` を付けない。** flex の既定
  （stretch）が効かなくなり、ボタンが全幅にならない
- ⚠️ **エディタのプレビューは画面幅で切り替える。** `previewStyle: "vertical"`
  のままだと狭い画面で本文とプレビューが半分ずつになって書けない
- 構造は `test/antpress_web/responsive_test.exs` で固定してある

### ⚠️ ナビは `root.html.heex` ではなく `Layouts.app` に置く

`current_user` と `current_developer` を入れる plug は**どちらも全リクエストで
走る。** `root.html.heex` は conn の assign を見るので、両方でログインしていると
**クライアント側の画面でも developer のナビが出て、記事・カテゴリ・画像へ
移動できなくなる**（実際にそうなった）。

`Layouts.app` なら「どちらの assign を渡されたか」＝ページ自身がどちら側かで
決まる。出し分けは `test/antpress_web/live/navigation_test.exs` で固定してある。

⚠️ `/`（`page_html/home.html.heex`）は Phoenix の初期テンプレートのままで
`Layouts.app` を使っていない。ログイン中はそれぞれの管理画面へリダイレクトする。

### ⚠️ 時系列で並べる一覧のテーブルは timestamps を `utc_datetime_usec` にする

`images` と `blog_articles` がこれ。秒精度だと同一秒のレコードが同着になり、
第 2 キー（ランダムな UUID）で順序が決まる。**「まとめて上げた画像が
ばらばらに並ぶ」「保存したのに一覧の先頭に来ない」**という見え方になる。
どちらも実際にテストで検出した。

`blog_categories` のように `position` で並べるテーブルは秒精度のままでよい。

### ⚠️ `.gitignore` の env パターンは `.env*`（`.env.*` にしない）

`.env.*` だと Finder の複製で作られる **`.env copy.example`** のような
スペース入りの名前がすり抜ける。実際に本物の接続情報が入ったファイルが
未追跡で出た。`!.env.example` で雛形だけ追跡対象に戻している。

### ⚠️ sudo モードでページごと塞がない

`mix phx.gen.auth` は設定画面に `on_mount {..., :require_sudo_mode}` を付ける。
**最後の認証から 10 分を過ぎるとログイン画面へ飛ばされる。**

記事・カテゴリ・画像には自由に行けるのに設定画面だけ弾かれるので、
理由が分からず不具合に見える（実際に報告があった）。

**保護が要る操作はページごと分ける。**

| パス | 保護 |
| --- | --- |
| `/client/settings` `/developers/settings` | なし（表示だけ） |
| `/client/settings/password` `/developers/settings/password` | **sudo モード** |

こうすると「保護が要る操作」と「そうでない表示」の境界が URL と一致する。

⚠️ **保護が要るページでもログイン画面へリダイレクトしない。**
どこから来たのか分からなくなる。その場に案内と「ログインし直す」を出す。
変更そのものは LiveView のイベントとコントローラの両方で
`sudo_mode?/1` を確認している（fail closed のまま）。

⚠️ `true = sudo_mode?(user)` のままだと、古い画面から送られたときに
`MatchError` で 500 になる。案内を出して閉じる形にしてある。

### 言語と UI の文言

- ドキュメント・UI・コミットメッセージは**日本語**

#### ⚠️ 画面に技術用語を出さない

クライアント側の画面を使うのは**ラーメン屋のオーナーや美容室の店長**で、
WEB の知識は前提にできない。**WordPress 用語をそのまま出さない。**

| DB / コード | 画面の表示 | 補足 |
| --- | --- | --- |
| `blog_articles.slug` | **記事のアドレス** | ⚠️ **入力欄は出さない。**システム生成で変更不可（→ 下記） |
| `blog_categories.slug` | **カテゴリのアドレス** | 同上 |
| `images.alt_text` | **画像の説明** | 「代替テキスト」も専門用語 |
| `clients.slug` | **識別名** | ⚠️ こちらは URL に使わない管理用の識別子。記事・カテゴリとは呼び方を分ける |

- 「スラッグ」「パーマリンク」「エンドポイント」のような語を画面に出さない
- 制約を書くときは**具体例を添える**
  （「半角の英字（小文字）・数字・ハイフン」＋ URL の実例）
- **検証エラーの文言も同じ語彙に揃える。**
  ラベルが「記事のアドレス」なのにエラーが「スラッグが不正です」だと通じない
- ⚠️ **ボタンをアイコンだけにしない。** チェックマークだけの保存ボタンは
  「どうやって保存するのか分からない」と言われた。`aria-label` は
  スクリーンリーダー用で、目で見ている人には何も伝わらない
- ⚠️ **入力欄にラベルを付ける。** placeholder だけだと、入力した瞬間に
  何の欄か分からなくなる
- ⚠️ **「〜の場合があります」で濁さない。** サーバー側で状態が分かるなら
  言い切る（例: 「変更にはログインし直しが必要になる場合があります」→
  `sudo_mode?` を見て「いま変更できます」/「変更するにはログインし直しが
  必要です」）。読んだ人が次に何をすればよいか決められない文言にしない
- ⚠️ **文言に数字を直接書かない。** しきい値は
  `Accounts.sudo_mode_minutes/0` のように値を返す関数から出す。
  直接書くと、しきい値を変えたときに説明だけ古くなる
- ⚠️ **記事フォームから同じタブで別画面へ誘導しない。**
  書きかけの本文が失われる。必要な操作はモーダル内で完結させるか、
  リンクを `target="_blank"` にする（サムネイル選択のモーダルで実際に起きた）
