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

## 規約

### 命名

- ブログ領域のテーブルは **`blog_` 接頭辞**: `blog_articles`, `blog_categories`
- コンテキストは `AntPress.Blog`。将来 EC は `AntPress.Commerce`
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

### 言語

- ドキュメント・UI・コミットメッセージは**日本語**
