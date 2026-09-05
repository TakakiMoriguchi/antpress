# antpress

小規模 HP 向けの**マルチテナント型ヘッドレス CMS**。

制作者（developer）単位で提供し、その配下のクライアント（店舗・企業）が
自分のコンテンツを管理する。コンテンツは配信 API 経由で、別途構築された
HP（Astro / React）から取得される。

## 設計思想

WordPress は「作ろうと思えば何でも作れる」が、実際に使う機能はだいたい決まっている。
antpress はその「よく使うもの」に絞り、**スキーマの自由度を持たせない**。
必要なものは最初から固定で用意する。

## 構造

```
admin（運営者）
  └─ developer（HP 制作を行うエンジニア）
       └─ client（店舗・企業）
            └─ users（owner / staff）
```

## 機能スコープ

| 提供する | 提供しない |
| --- | --- |
| ブログ（基本 / AI プラン） | スキーマのカスタム定義 |
| 画像管理 | 表示テーマ・ページビルダー |
| お問い合わせ（フォーム設定・受付・転送） | 下書きプレビュー |
| Webhook（公開時に HP を再ビルド） | メニュー・店舗情報管理 |
| コンテンツ配信 API | EC（将来検討） |
| アカウント管理 | 決済（antpress の外で手動） |

## 技術スタック

| 領域 | 選定 |
| --- | --- |
| アプリケーション | Elixir / Phoenix（LiveView）・モノリス |
| データベース | PostgreSQL（Supabase） |
| 画像ストレージ | Supabase Storage |
| ホスティング | Fly.io（東京リージョン） |
| メール配信 | Resend |
| AI 生成 | Claude API / Claude Sonnet 5（developer の BYOK） |

## ドキュメント

**実装前に `docs/DECISIONS.md` を読むこと。** 撤回された判断も理由付きで残してあり、
同じ議論を繰り返さないための記録になっている。

| ファイル | 内容 |
| --- | --- |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | **決定事項と決定ログ。**まずここ |
| [`docs/DATA-MODEL.md`](docs/DATA-MODEL.md) | 11 テーブルの定義、索引、運用上の設計判断 |
| [`docs/SCREENS.md`](docs/SCREENS.md) | 24 画面、URL 空間、権限、ワイヤーフレーム |
| [`docs/API-GUIDE.md`](docs/API-GUIDE.md) | 配信 API の実装ガイド（HP 構築時に読む） |
| [`docs/TECH-NOTES.md`](docs/TECH-NOTES.md) | 判断材料の記録（なぜその選定になったか） |
| [`docs/VENDORED-ASSETS.md`](docs/VENDORED-ASSETS.md) | 同梱している外部アセットの出所・更新手順 |

## 開発

ツールのバージョンは `mise.toml` で固定してある（Erlang 28 / Elixir 1.20 / Node 24）。

```sh
mise install            # 初回のみ
mix deps.get
docker compose up -d    # 開発用 PostgreSQL 17（ポート 5433）
mix ecto.create
mix phx.server          # http://localhost:4001
```

| 用途 | ポート |
| --- | --- |
| Phoenix（dev） | **4001** |
| Phoenix（test） | 4002 |
| PostgreSQL（dev） | **5433** |

既定値（4000 / 5432）から変更している。理由は [`CLAUDE.md`](CLAUDE.md) を参照。

本番は Supabase（東京リージョン）＋ Fly.io。`.env.example` をコピーして値を埋める。

### 開発用アカウント

**ローカルの開発 DB 専用。** 本番には存在しないし、作らないこと。

| | URL | メールアドレス | パスワード |
| --- | --- | --- | --- |
| developer / admin | http://localhost:4001/developers/log-in | `takaki@antpress.local` | `antpress-dev-2026` |
| client（オーナー） | http://localhost:4001/client/log-in | `owner@ramen-taro.local` | `antpress-dev-2026` |

パスワードを使わずマジックリンクでも入れる。ログイン画面で「メールでログイン」を
押し、http://localhost:4001/dev/mailbox でメールを開いてリンクをクリックする。

最初の admin を作り直す場合:

```sh
ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=... mix run priv/repo/seeds.exs
```

## 状態

実装順序は [`docs/DATA-MODEL.md`](docs/DATA-MODEL.md) の 6 章を参照。

| # | 内容 | 状態 |
| --- | --- | --- |
| 1 | `developers` ＋ ログイン | 完了 |
| 2 | `clients` ＋ クライアント管理 | 完了 |
| 2b | `users` ＋ クライアントログイン | 完了 |
| 3 | `blog_categories` ＋ プリセット投入 | 完了 |
| 4 | `images` ＋ Supabase Storage 連携 | 完了 |
| 5 | `blog_articles`（基本プラン / Toast UI Editor） | 完了 |
| 6 | `api_keys` ＋ 配信 API ＋ OpenAPI | 未着手 |
| 7 | Webhook | 未着手 |
| 8 | お問い合わせ ＋ Resend | 未着手 |
| 9 | AI プラン | 未着手 |

未実装の画面: 招待フロー（developer 発行 / オーナー・スタッフ発行）、
developer の Anthropic API キー設定。

## AI エージェント向け

[`CLAUDE.md`](CLAUDE.md)（プロジェクト固有のルール）と
[`AGENTS.md`](AGENTS.md)（Phoenix / Elixir の作法・Phoenix 生成）を参照。
