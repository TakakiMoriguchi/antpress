defmodule AntPress.BlogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `AntPress.Blog` context.
  """

  def unique_category_slug, do: "cat-#{System.unique_integer([:positive])}"

  @doc """
  Generate a category.
  """
  def category_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "お知らせ",
        position: 0,
        slug: unique_category_slug()
      })

    {:ok, category} = AntPress.Blog.create_category(scope, attrs)
    category
  end

  def unique_article_slug, do: "article-#{System.unique_integer([:positive])}"

  @doc """
  記事を生成する。既定は下書き。

  公開済みにしたいときは `%{status: :published}`、
  予約投稿にしたいときは `published_at` に未来の日時を渡す。
  """
  def article_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        title: "新メニューのお知らせ",
        slug: unique_article_slug(),
        body: "# 見出し\n\n本文です。"
      })

    {:ok, article} = AntPress.Blog.create_article(scope, attrs)
    article
  end

  @doc "公開済みの記事（公開日時は過去）"
  def published_article_fixture(scope, attrs \\ %{}) do
    article_fixture(
      scope,
      Enum.into(attrs, %{
        status: :published,
        published_at: DateTime.add(DateTime.utc_now(:second), -3600, :second)
      })
    )
  end

  @doc "予約投稿の記事（公開日時は未来）"
  def scheduled_article_fixture(scope, attrs \\ %{}) do
    article_fixture(
      scope,
      Enum.into(attrs, %{
        status: :published,
        published_at: DateTime.add(DateTime.utc_now(:second), 3600, :second)
      })
    )
  end
end
