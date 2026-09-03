# antpress 配信 API 実装ガイド

> **対象読者**: antpress の配信 API を使って HP を構築する開発者
> **前提構成**: Astro + React
> 最終更新: 2026-09-03

機械可読な仕様は OpenAPI（`/api/openapi`）を参照してください。
このドキュメントは**仕様には書けない運用ルール**を扱います。

---

## 1. 絶対に守るルール

### 1.1 API キーはサーバーサイドでしか使わない

配信 API キーは**シークレット**です。ブラウザに露出した時点で、そのクライアントの
全コンテンツが第三者から読める状態になります。

- ✅ Astro の frontmatter（ビルド時 / サーバー）で取得する
- ✅ 取得したデータを props で React コンポーネントに渡す
- ❌ **React island の中で fetch しない**
- ❌ **`useEffect` 内で fetch しない**

### 1.2 環境変数名に `PUBLIC_` を付けない

Astro は **`PUBLIC_` プレフィックスの付いた環境変数をクライアントバンドルに埋め込みます。**

```bash
# ✅ 正しい。サーバー / ビルド時のみで参照される
ANTPRESS_API_KEY=ap_live_xxxxx

# ❌ クライアントに埋め込まれる。キーが漏れる
PUBLIC_ANTPRESS_API_KEY=ap_live_xxxxx
```

### 1.3 本番とステージングでキーを分ける

antpress は 1 クライアントに複数キーを発行できます。環境ごとに分けておけば、
片方が漏れてももう片方を止めずに失効・再発行できます。

---

## 2. 正しい実装パターン

### 2.1 記事一覧

```astro
---
// src/pages/blog/index.astro
// この frontmatter はビルド時（サーバー）に実行される。ブラウザには出ない。
import ArticleList from '../../components/ArticleList.jsx';

const res = await fetch('https://antpress.example.com/api/v1/articles', {
  headers: { Authorization: `Bearer ${import.meta.env.ANTPRESS_API_KEY}` },
});
const { articles } = await res.json();
---

<!-- 取得済みのデータを props で渡す -->
<ArticleList articles={articles} />
```

```jsx
// src/components/ArticleList.jsx
// props を受け取るだけ。fetch は一切しない。
export default function ArticleList({ articles }) {
  return (
    <ul>
      {articles.map((a) => (
        <li key={a.id}>
          <a href={`/blog/${a.slug}`}>{a.title}</a>
        </li>
      ))}
    </ul>
  );
}
```

### 2.2 記事詳細（動的ルート）

```astro
---
// src/pages/blog/[slug].astro
export async function getStaticPaths() {
  const res = await fetch('https://antpress.example.com/api/v1/articles', {
    headers: { Authorization: `Bearer ${import.meta.env.ANTPRESS_API_KEY}` },
  });
  const { articles } = await res.json();

  return articles.map((article) => ({
    params: { slug: article.slug },
    props: { article },
  }));
}

const { article } = Astro.props;
---

<article>
  <h1>{article.title}</h1>
  <div set:html={article.body_html} />
</article>
```

`getStaticPaths` もビルド時に実行されるため、ここでのキー利用は安全です。

---

## 3. アンチパターン

### 3.1 React island 内での fetch

```jsx
// ❌ 絶対にやらない
import { useEffect, useState } from 'react';

export default function ArticleList() {
  const [articles, setArticles] = useState([]);

  useEffect(() => {
    // このコードはブラウザで実行される。キーがバンドルに含まれ、
    // DevTools の Network タブと JS ファイルの両方から読める。
    fetch('https://antpress.example.com/api/v1/articles', {
      headers: { Authorization: `Bearer ${import.meta.env.PUBLIC_ANTPRESS_API_KEY}` },
    })
      .then((r) => r.json())
      .then((d) => setArticles(d.articles));
  }, []);

  return <ul>{/* ... */}</ul>;
}
```

**この間違いは開発中に必ず失敗します。** antpress は CORS を一切許可していないため、
ブラウザからのリクエストはブロックされます。つまり**気づかないまま本番に出ることはない**
設計になっています（フェイルセーフ）。

ただし CORS はブラウザにしか効きません。`curl` やサーバーサイドのスクリプトからは
キーだけで叩けてしまうので、**露出させないこと自体が防御の本体**です。

---

## 4. API の性質

| 項目 | 内容 |
| --- | --- |
| メソッド | 読み取り専用（`GET` のみ） |
| 認証 | `Authorization: Bearer <API キー>`。**認証なしのアクセスは全て拒否** |
| スコープ | キーはクライアント単位。他クライアントのコンテンツは取得不可 |
| 返るデータ | **公開済みの記事のみ。** 下書きは API から一切取得できない |
| CORS | **許可しない。** ブラウザからの直接アクセスは不可 |
| レート制限 | キー単位で 300 req/min |
| 契約停止時 | **`403` を返す。** メッセージに停止理由が含まれる。公開中の HP（静的 HTML）は動き続けるが、**次回のビルドが失敗する** |

### 下書きプレビューは提供しません

未公開記事を HP のデザインで確認する機能は antpress のスコープ外です。
下書きは配信 API から取得できません。

---

## 5. キーが漏れたときの対応

1. antpress の管理画面で該当キーを**失効**させる
2. 新しいキーを発行する
3. HP の環境変数を差し替えて再デプロイする

複数キーを発行しておけば、失効から差し替えまでの間もサイトを止めずに済みます。
