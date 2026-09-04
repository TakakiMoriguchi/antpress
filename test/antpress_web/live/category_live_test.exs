defmodule AntPressWeb.CategoryLiveTest do
  use AntPressWeb.ConnCase

  import Phoenix.LiveViewTest
  import AntPress.BlogFixtures

  @create_attrs %{name: "季節限定", position: 10, slug: "seasonal"}
  @update_attrs %{name: "季節のおすすめ", position: 11, slug: "seasonal-pick"}
  @invalid_attrs %{name: nil, position: nil, slug: nil}

  setup :register_and_log_in_user

  defp create_category(%{scope: scope}) do
    category = category_fixture(scope)

    %{category: category}
  end

  describe "Index" do
    setup [:create_category]

    test "lists all blog_categories", %{conn: conn, category: category} do
      {:ok, _index_live, html} = live(conn, ~p"/client/categories")

      assert html =~ "カテゴリ"
      assert html =~ category.name
    end

    test "saves new category", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/client/categories")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "カテゴリを追加")
               |> render_click()
               |> follow_redirect(conn, ~p"/client/categories/new")

      assert render(form_live) =~ "カテゴリを追加"

      assert form_live
             |> form("#category-form", category: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#category-form", category: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/client/categories")

      html = render(index_live)
      assert html =~ "Category created successfully"
      assert html =~ "季節限定"
    end

    test "updates category in listing", %{conn: conn, category: category} do
      {:ok, index_live, _html} = live(conn, ~p"/client/categories")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#blog_categories-#{category.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/client/categories/#{category}/edit")

      assert render(form_live) =~ "カテゴリを編集"

      assert form_live
             |> form("#category-form", category: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#category-form", category: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/client/categories")

      html = render(index_live)
      assert html =~ "Category updated successfully"
      assert html =~ "季節のおすすめ"
    end

    test "deletes category in listing", %{conn: conn, category: category} do
      {:ok, index_live, _html} = live(conn, ~p"/client/categories")

      assert index_live
             |> element("#blog_categories-#{category.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#blog_categories-#{category.id}")
    end
  end

  describe "Show" do
    setup [:create_category]

    test "displays category", %{conn: conn, category: category} do
      {:ok, _show_live, html} = live(conn, ~p"/client/categories/#{category}")

      assert html =~ "Show Category"
      assert html =~ category.name
    end

    test "updates category and returns to show", %{conn: conn, category: category} do
      {:ok, show_live, _html} = live(conn, ~p"/client/categories/#{category}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/client/categories/#{category}/edit?return_to=show")

      assert render(form_live) =~ "カテゴリを編集"

      assert form_live
             |> form("#category-form", category: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#category-form", category: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/client/categories/#{category}")

      html = render(show_live)
      assert html =~ "Category updated successfully"
      assert html =~ "季節のおすすめ"
    end
  end
end
