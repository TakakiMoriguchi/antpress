defmodule AntPressWeb.ArticleLive.Form do
  @moduledoc """
  記事編集（→ `docs/SCREENS.md` C4）。**最重要画面。**

  ## ⚠️ Toast UI Editor の組み込み

  エディタは JS が DOM を構築するので、囲みに **`phx-update="ignore"`** を
  付ける。付けないと LiveView の DOM パッチでエディタが壊れる
  （→ `docs/DECISIONS.md` 4.3）。

  **本文の hidden input も `ignore` の中に置いている。** LiveView は中身を
  更新しないが、フォーム送信時のシリアライズは DOM を読むので値は届く。
  外に置くと、他のフィールドの検証で再描画されたときに JS が入れた値が
  サーバー側の古い値へ巻き戻る。

  囲みの `id` に記事 ID を含めているのは、別の記事へ patch 遷移したときに
  **要素ごと差し替えてエディタを作り直させる**ため。`ignore` は中身を
  更新しないので、id が同じままだと前の記事の本文が残る。

  ## 522KB のエディタを全ページに読ませない

  Toast UI は `app.js` にバンドルせず `priv/static/vendor/` から
  `<script>` で読む。**この画面だけが読む**
  （→ `docs/VENDORED-ASSETS.md`）。
  """
  use AntPressWeb, :live_view

  alias AntPress.{Blog, Media}
  alias AntPress.Blog.Article

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <%!-- このページだけで読む。app.js には入れない（522KB） --%>
      <link
        phx-track-static
        rel="stylesheet"
        href={~p"/vendor/toastui-editor/toastui-editor.min.css"}
      />
      <link
        phx-track-static
        rel="stylesheet"
        href={~p"/vendor/toastui-editor/toastui-editor-dark.min.css"}
      />
      <script phx-track-static src={~p"/vendor/toastui-editor/toastui-editor-all.min.js"}>
      </script>
      <script phx-track-static src={~p"/vendor/toastui-editor/i18n-ja-jp.min.js"}>
      </script>

      <.header>
        {@page_title}
        <:subtitle>スラッグは記事 URL に使われます。公開日時を未来にすると予約投稿になります。</:subtitle>
      </.header>

      <.form for={@form} id="article-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label="タイトル" />
        <.input field={@form[:slug]} type="text" label="スラッグ" placeholder="new-menu-2026" />

        <div class="mt-4">
          <label class="label" for="article-editor-root">本文</label>
          <%!-- ⚠️ phx-update="ignore" は必須。本文の hidden input も中に置く --%>
          <div
            id={"article-editor-#{@editor_key}"}
            phx-hook=".ToastEditor"
            phx-update="ignore"
            data-mode={editor_mode(@editor_format)}
            data-upload-path={~p"/client/editor/images"}
          >
            <%!-- 本文の初期値はこの hidden input が単一の出所。
                  フック側が読んでエディタに流し込み、編集中は書き戻す --%>
            <div id="article-editor-root"></div>
            <input type="hidden" name="article[body]" value={@editor_body} />
            <input type="hidden" name="article[body_format]" value={@editor_format} />
          </div>
        </div>

        <.input
          field={@form[:category_id]}
          type="select"
          label="カテゴリ"
          prompt="未分類"
          options={@category_options}
        />

        <div class="mt-4">
          <span class="label">サムネイル</span>
          <div class="mt-1 flex items-center gap-4">
            <img
              :if={@thumbnail}
              src={Media.public_url(@thumbnail)}
              alt={@thumbnail.alt_text || ""}
              class="size-24 rounded bg-base-200 object-cover"
            />
            <div :if={is_nil(@thumbnail)} class="size-24 rounded bg-base-200" aria-hidden="true" />
            <div class="flex flex-col items-start gap-1">
              <.button type="button" phx-click="open-picker">画像を選択</.button>
              <.button
                :if={@thumbnail}
                type="button"
                phx-click="clear-thumbnail"
                class="btn-ghost btn-sm"
              >
                外す
              </.button>
            </div>
          </div>
          <input
            type="hidden"
            name="article[thumbnail_image_id]"
            value={@form[:thumbnail_image_id].value}
          />
          <p
            :for={msg <- Enum.map(@form[:thumbnail_image_id].errors, &translate_error(&1))}
            class="mt-1 text-sm text-error"
          >
            {msg}
          </p>
        </div>

        <.input
          field={@form[:status]}
          type="select"
          label="公開状態"
          options={[{"下書き", "draft"}, {"公開", "published"}]}
        />
        <.input
          field={@form[:published_at]}
          type="datetime-local"
          label="公開日時"
        />
        <p class="mt-1 text-sm text-base-content/60">
          空のまま「公開」にすると現在時刻で公開します。未来の日時を入れると予約投稿になります。
        </p>

        <footer class="mt-6 flex gap-2">
          <.button phx-disable-with="保存中..." variant="primary">保存</.button>
          <.button navigate={~p"/client/articles"}>キャンセル</.button>
        </footer>
      </.form>

      <%!-- サムネイル選択（C6 の画像をモーダルで選ぶ） --%>
      <dialog :if={@picker_open?} id="image-picker" class="modal modal-open">
        <div class="modal-box max-w-3xl">
          <h3 class="text-lg font-semibold">サムネイルを選択</h3>

          <p :if={@images == []} class="mt-6 text-center text-base-content/60">
            画像がありません。<.link navigate={~p"/client/images"} class="link">画像管理</.link>からアップロードしてください。
          </p>

          <div
            :if={@images != []}
            class="mt-4 grid max-h-96 grid-cols-3 gap-3 overflow-y-auto sm:grid-cols-4"
          >
            <button
              :for={image <- @images}
              type="button"
              phx-click="select-thumbnail"
              phx-value-id={image.id}
              class="rounded border border-base-300 p-1 hover:border-primary"
            >
              <img
                src={Media.public_url(image)}
                alt={image.alt_text || image.filename}
                loading="lazy"
                class="aspect-square w-full rounded object-cover"
              />
              <span class="mt-1 block truncate text-xs">{image.filename}</span>
            </button>
          </div>

          <div class="modal-action">
            <.button type="button" phx-click="close-picker">閉じる</.button>
          </div>
        </div>
        <label class="modal-backdrop" phx-click="close-picker">閉じる</label>
      </dialog>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ToastEditor">
        export default {
          mounted() {
            const Editor = window.toastui && window.toastui.Editor
            if (!Editor) {
              this.el.querySelector("#article-editor-root").textContent =
                "エディタの読み込みに失敗しました。ページを再読み込みしてください。"
              return
            }

            this.bodyInput = this.el.querySelector('input[name="article[body]"]')
            this.formatInput = this.el.querySelector('input[name="article[body_format]"]')
            const uploadPath = this.el.dataset.uploadPath
            const csrfToken = document
              .querySelector("meta[name='csrf-token']")
              .getAttribute("content")

            this.editor = new Editor({
              el: this.el.querySelector("#article-editor-root"),
              height: "480px",
              language: "ja-JP",
              usageStatistics: false,
              initialEditType: this.el.dataset.mode,
              previewStyle: "vertical",
              initialValue: this.bodyInput.value || "",
              // 画像はサーバーへ送って URL を差し込む。
              // これを渡さないと Toast UI は画像を base64 で本文に埋める
              hooks: {
                addImageBlobHook: async (blob, callback) => {
                  const form = new FormData()
                  form.append("file", blob, blob.name || "image.png")

                  try {
                    const res = await fetch(uploadPath, {
                      method: "POST",
                      headers: {"x-csrf-token": csrfToken},
                      body: form,
                    })
                    const data = await res.json()

                    if (res.ok) {
                      callback(data.url, data.altText || "")
                    } else {
                      window.alert(data.error || "画像のアップロードに失敗しました")
                    }
                  } catch (e) {
                    window.alert("画像のアップロードに失敗しました")
                  }
                },
              },
            })

            // 管理画面のテーマに合わせる。付けないと暗い画面で白いエディタになる
            this.applyTheme()

            this.editor.on("change", () => this.sync())
            this.editor.on("blur", () => this.sync())

            // モード切り替えは change を伴わないことがあるのでタブを直接見る
            const modeSwitch = this.el.querySelector(".toastui-editor-mode-switch")
            if (modeSwitch) {
              modeSwitch.addEventListener("click", () => setTimeout(() => this.sync(), 0))
            }

            this.sync()
          },

          applyTheme() {
            const root = document.documentElement
            const explicit = root.getAttribute("data-theme")
            const dark =
              explicit === "dark" ||
              (!explicit && window.matchMedia("(prefers-color-scheme: dark)").matches)

            this.el
              .querySelectorAll(".toastui-editor-defaultUI")
              .forEach(node => node.classList.toggle("toastui-editor-dark", dark))
          },

          sync() {
            if (!this.editor) return
            // ⚠️ getHTML() は使わない。HTML はサーバー側で Markdown から作る
            this.bodyInput.value = this.editor.getMarkdown()
            this.formatInput.value = this.editor.isMarkdownMode() ? "markdown" : "rich_text"
          },

          destroyed() {
            if (this.editor) this.editor.destroy()
          },
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:category_options, category_options(scope))
     |> assign(:picker_open?, false)
     |> assign(:images, [])
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    scope = socket.assigns.current_user
    article = %Article{}

    socket
    |> assign(:page_title, "記事を書く")
    |> assign(:article, article)
    |> assign(:editor_key, "new")
    |> assign_editor_state(article)
    |> assign(:thumbnail, nil)
    |> assign_form(Blog.change_article(scope, article))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_user
    article = Blog.get_article!(scope, id)

    socket
    |> assign(:page_title, "記事を編集")
    |> assign(:article, article)
    |> assign(:editor_key, article.id)
    |> assign_editor_state(article)
    |> assign(:thumbnail, article.thumbnail_image)
    |> assign_form(Blog.change_article(scope, article))
  end

  @impl true
  def handle_event("validate", %{"article" => attrs}, socket) do
    changeset =
      Blog.change_article(socket.assigns.current_user, socket.assigns.article, attrs)

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  @impl true
  def handle_event("save", %{"article" => attrs}, socket) do
    save_article(socket, socket.assigns.live_action, attrs)
  end

  @impl true
  def handle_event("open-picker", _params, socket) do
    {:noreply,
     socket
     |> assign(:images, Media.list_images(socket.assigns.current_user))
     |> assign(:picker_open?, true)}
  end

  @impl true
  def handle_event("close-picker", _params, socket) do
    {:noreply, assign(socket, :picker_open?, false)}
  end

  @impl true
  def handle_event("select-thumbnail", %{"id" => id}, socket) do
    scope = socket.assigns.current_user
    # ⚠️ スコープ付きで引き直す。フォームから来た id を信用しない
    image = Media.get_image!(scope, id)

    {:noreply,
     socket
     |> assign(:thumbnail, image)
     |> assign(:picker_open?, false)
     |> put_form_change(:thumbnail_image_id, image.id)}
  end

  @impl true
  def handle_event("clear-thumbnail", _params, socket) do
    {:noreply,
     socket
     |> assign(:thumbnail, nil)
     |> put_form_change(:thumbnail_image_id, nil)}
  end

  defp save_article(socket, :new, attrs) do
    case Blog.create_article(socket.assigns.current_user, attrs) do
      {:ok, article} ->
        {:noreply,
         socket
         |> put_flash(:info, "記事を作成しました")
         |> push_navigate(to: ~p"/client/articles/#{article}/edit")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_article(socket, :edit, attrs) do
    case Blog.update_article(socket.assigns.current_user, socket.assigns.article, attrs) do
      {:ok, article} ->
        {:noreply,
         socket
         |> put_flash(:info, "記事を保存しました")
         |> assign(:article, article)
         |> assign(:thumbnail, article.thumbnail_image)
         |> assign_form(Blog.change_article(socket.assigns.current_user, article))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "article"))
  end

  # フォームの値だけ差し替える。エディタの中身には触らない
  defp put_form_change(socket, field, value) do
    changeset =
      socket.assigns.form.source
      |> Ecto.Changeset.put_change(field, value)

    assign_form(socket, changeset)
  end

  # エディタの初期値。**再描画では変えない**（`phx-update="ignore"` なので
  # 変えても反映されず、値が食い違うだけになる）
  defp assign_editor_state(socket, %Article{} = article) do
    socket
    |> assign(:editor_body, article.body || "")
    |> assign(:editor_format, to_string(article.body_format || :markdown))
  end

  # body_format と Toast UI の initialEditType の対応（→ Article の説明）
  defp editor_mode("rich_text"), do: "wysiwyg"
  defp editor_mode(_markdown), do: "markdown"

  defp category_options(scope) do
    Enum.map(Blog.list_blog_categories(scope), &{&1.name, &1.id})
  end
end
