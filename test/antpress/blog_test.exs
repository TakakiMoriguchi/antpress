defmodule AntPress.BlogTest do
  use AntPress.DataCase

  alias AntPress.Blog

  describe "blog_categories" do
    alias AntPress.Blog.Category

    import AntPress.AccountsFixtures, only: [client_scope_fixture: 0]
    import AntPress.BlogFixtures

    @invalid_attrs %{name: nil, position: nil, slug: nil}

    test "list_blog_categories/1 はスコープ内のカテゴリのみ返す" do
      scope = client_scope_fixture()
      other_scope = client_scope_fixture()
      category = category_fixture(scope)
      other_category = category_fixture(other_scope)

      # クライアント作成時にプリセットが投入されるため 0 件から始まらない
      # （→ docs/DECISIONS.md 3.2）
      ids = Blog.list_blog_categories(scope) |> Enum.map(& &1.id)
      other_ids = Blog.list_blog_categories(other_scope) |> Enum.map(& &1.id)

      assert category.id in ids
      refute other_category.id in ids
      assert other_category.id in other_ids
      refute category.id in other_ids
    end

    test "クライアント作成時にプリセットのカテゴリが投入される" do
      scope = client_scope_fixture()

      names = Blog.list_blog_categories(scope) |> Enum.map(& &1.name)
      assert names == ["お知らせ", "ブログ", "ニュース"]
    end

    test "list_blog_categories/1 は position 順に並べる" do
      scope = client_scope_fixture()
      category_fixture(scope, %{name: "先頭", slug: "first", position: -1})

      assert [%{name: "先頭"} | _] = Blog.list_blog_categories(scope)
    end

    test "get_category!/2 returns the category with given id" do
      scope = client_scope_fixture()
      category = category_fixture(scope)
      other_scope = client_scope_fixture()
      assert Blog.get_category!(scope, category.id) == category
      assert_raise Ecto.NoResultsError, fn -> Blog.get_category!(other_scope, category.id) end
    end

    test "create_category/2 with valid data creates a category" do
      valid_attrs = %{name: "季節限定", position: 10, slug: "seasonal"}
      scope = client_scope_fixture()

      assert {:ok, %Category{} = category} = Blog.create_category(scope, valid_attrs)
      assert category.name == "季節限定"
      assert category.position == 10
      assert category.slug == "seasonal"
      assert category.client_id == scope.client.id
    end

    test "create_category/2 with invalid data returns error changeset" do
      scope = client_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Blog.create_category(scope, @invalid_attrs)
    end

    test "update_category/3 with valid data updates the category" do
      scope = client_scope_fixture()
      category = category_fixture(scope)
      update_attrs = %{name: "最新情報", position: 5, slug: "latest"}

      assert {:ok, %Category{} = category} = Blog.update_category(scope, category, update_attrs)
      assert category.name == "最新情報"
      assert category.position == 5
      assert category.slug == "latest"
    end

    test "update_category/3 with invalid scope raises" do
      scope = client_scope_fixture()
      other_scope = client_scope_fixture()
      category = category_fixture(scope)

      assert_raise MatchError, fn ->
        Blog.update_category(other_scope, category, %{})
      end
    end

    test "update_category/3 with invalid data returns error changeset" do
      scope = client_scope_fixture()
      category = category_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Blog.update_category(scope, category, @invalid_attrs)
      assert category == Blog.get_category!(scope, category.id)
    end

    test "delete_category/2 deletes the category" do
      scope = client_scope_fixture()
      category = category_fixture(scope)
      assert {:ok, %Category{}} = Blog.delete_category(scope, category)
      assert_raise Ecto.NoResultsError, fn -> Blog.get_category!(scope, category.id) end
    end

    test "delete_category/2 with invalid scope raises" do
      scope = client_scope_fixture()
      other_scope = client_scope_fixture()
      category = category_fixture(scope)
      assert_raise MatchError, fn -> Blog.delete_category(other_scope, category) end
    end

    test "change_category/2 returns a category changeset" do
      scope = client_scope_fixture()
      category = category_fixture(scope)
      assert %Ecto.Changeset{} = Blog.change_category(scope, category)
    end
  end
end
