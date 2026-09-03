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

## 状態

設計フェーズ完了。実装は未着手。

実装順序は [`docs/DATA-MODEL.md`](docs/DATA-MODEL.md) の 6 章を参照。
