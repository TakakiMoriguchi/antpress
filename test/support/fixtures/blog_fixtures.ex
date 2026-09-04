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
end
