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

  ## サムネイル選択のモーダルでアップロードまで完結させる

  ⚠️ **ここから画像管理へリンクで飛ばさない。書きかけの記事が失われる。**
  画像が 1 枚も無いときに「画像管理へ」と促すと、記事を書き始めた人が
  必ず作業を失う導線になる。

  説明文の編集や削除は画像管理で行うが、そちらへのリンクは
  `target="_blank"` にして同じ事故を防ぐ。

  ## アドレス（`slug`）の入力欄は出さない

  システムが決めて以後変えない（→ `AntPress.Blog.Article`）。
  編集画面では確認用に読み取り専用で表示する。

  ## 522KB のエディタを全ページに読ませない

  Toast UI は `app.js` にバンドルせず `priv/static/vendor/` から読む。
  **この画面だけが読む**（→ `docs/VENDORED-ASSETS.md`）。

  ## ⚠️ `<script>` タグをテンプレートに書いてはいけない

  LiveView のテンプレートに `<script src=...>` を置くと、**live navigation
  で到達したときに実行されない。** LiveView は morphdom で DOM にパッチを
  当てるが、そうして挿入された `<script>` はブラウザが実行しないため
  （`innerHTML` で入れたスクリプトが動かないのと同じ）。

  URL を直接開いたときだけ動き、一覧から「記事を書く」を押すと
  `window.toastui` が未定義になる、という分かりにくい壊れ方をする
  （実際にそうなった）。

  そのため**フックが `mounted()` で動的に読み込む。** 読み込み先は
  `data-editor-*` 属性でサーバーから渡す（`~p` を通すのでパスの検証と
  キャッシュバスティングが効く）。
  """
  use AntPressWeb, :live_view

  alias AntPress.{Blog, Media}
  alias AntPress.Blog.Article
  alias AntPress.Media.Image
  alias AntPressWeb.{JST, MediaError}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        {@page_title}
        <:subtitle>公開日時を未来にすると、その日時まで公開されません（予約投稿）。</:subtitle>
      </.header>

      <.form for={@form} id="article-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label="タイトル" />
        <%!-- ⚠️ アドレスは入力させない。システムが決めて以後変えない
              （→ AntPress.Blog.Article の説明） --%>
        <div :if={@article.slug} class="mt-4">
          <span class="label">記事のアドレス</span>
          <p class="mt-1 font-mono text-sm">{@article.slug}</p>
          <p class="mt-1 text-sm text-base-content/60">
            サイトでこの記事を開くときのアドレスです。<br /> 公開後に変わると既存のリンクが開けなくなるため、自動で決まり、変更できません。
          </p>
        </div>

        <div class="mt-4">
          <label class="label" for="article-editor-root">本文</label>
          <%!-- ⚠️ phx-update="ignore" は必須。本文の hidden input も中に置く --%>
          <div
            id={"article-editor-#{@editor_key}"}
            phx-hook=".ToastEditor"
            phx-update="ignore"
            data-mode={editor_mode(@editor_format)}
            data-upload-path={~p"/client/editor/images"}
            data-editor-js={~p"/vendor/toastui-editor/toastui-editor-all.min.js"}
            data-editor-i18n={~p"/vendor/toastui-editor/i18n-ja-jp.min.js"}
            data-editor-css={~p"/vendor/toastui-editor/toastui-editor.min.css"}
            data-editor-dark-css={~p"/vendor/toastui-editor/toastui-editor-dark.min.css"}
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
          <p class="text-sm text-base-content/60">記事の一覧や SNS に出る画像です。1 枚だけ設定できます。</p>
          <div class="mt-2 flex items-center gap-4">
            <img
              :if={@thumbnail}
              src={Media.public_url(@thumbnail)}
              alt={@thumbnail.alt_text || ""}
              class="size-24 rounded bg-base-200 object-cover"
            />
            <div
              :if={is_nil(@thumbnail)}
              class="flex size-24 items-center justify-center rounded bg-base-200 text-xs text-base-content/50"
            >
              未設定
            </div>
            <div class="flex items-center gap-2">
              <%!-- 1 枚しか持てないので、設定済みなら「追加」ではなく「変更」 --%>
              <.button type="button" phx-click="open-picker">
                {if @thumbnail, do: "画像を変更", else: "画像を選択"}
              </.button>
              <.button
                :if={@thumbnail}
                type="button"
                phx-click="clear-thumbnail"
                class="btn-outline btn-sm"
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
        <%!-- ⚠️ 表示・入力は日本時間。保存は UTC（→ AntPressWeb.JST） --%>
        <.input
          field={@form[:published_at]}
          type="datetime-local"
          label="公開日時（日本時間）"
          value={JST.to_input_value(@form[:published_at].value)}
        />
        <p class="mt-1 text-sm text-base-content/60">
          <strong>「公開」を選んだときだけ使われます。</strong>空のままなら保存した時刻で公開します。<br />
          未来の日時を入れると、その日時になるまで公開されません（予約投稿）。<br /> 「下書き」のあいだは公開されないので、この欄は空のままで構いません。
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

          <%!-- ⚠️ ここから画像管理へリンクで飛ばさない。**書きかけの記事が失われる。**
                モーダルの中でアップロードまで完結させる --%>
          <form id="thumbnail-upload" phx-change="validate-thumbnail-upload" phx-submit="noop">
            <label
              class="mt-4 flex flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed border-base-300 px-4 py-6 text-center cursor-pointer hover:border-primary hover:bg-base-200/40"
              phx-drop-target={@uploads.thumbnail.ref}
            >
              <.icon name="hero-arrow-up-tray" class="size-5 text-base-content/60" />
              <span class="text-sm font-medium">
                クリックして選択、またはここにドラッグ＆ドロップ
              </span>
              <span class="text-xs text-base-content/60">
                アップロードするとサムネイルに設定されます
              </span>
              <.live_file_input upload={@uploads.thumbnail} class="sr-only" />
            </label>
          </form>

          <div :for={err <- upload_errors(@uploads.thumbnail)} class="alert alert-error mt-2">
            {upload_error_message(err)}
          </div>

          <div :for={entry <- @uploads.thumbnail.entries} class="mt-2 rounded-lg bg-base-200 p-3">
            <div class="flex items-center gap-3">
              <span class="flex-1 truncate text-sm">{entry.client_name}</span>
              <progress class="progress progress-primary w-32" value={entry.progress} max="100"></progress>
            </div>
            <p
              :for={err <- upload_errors(@uploads.thumbnail, entry)}
              class="mt-1 text-sm text-error"
            >
              {upload_error_message(err)}
            </p>
          </div>

          <p :if={@images == []} class="mt-6 text-center text-base-content/60">
            まだ画像がありません。上のエリアからアップロードしてください。
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

          <div class="modal-action items-center justify-between">
            <%!-- 説明の編集や削除は画像管理で行う。
                  ⚠️ target="_blank" にしないと書きかけの記事が失われる --%>
            <.link href={~p"/client/images"} target="_blank" rel="noopener" class="link text-sm">
              画像管理を開く（別のタブ）
            </.link>
            <.button type="button" phx-click="close-picker">閉じる</.button>
          </div>
        </div>
        <label class="modal-backdrop" phx-click="close-picker">閉じる</label>
      </dialog>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ToastEditor">
        // ⚠️ script タグをテンプレートに置くと live navigation で実行されない。
        // ここで動的に読み込む（モジュールスコープなので 1 ページにつき 1 回）
        let loading = null

        const loadCss = href => {
          if (document.querySelector(`link[data-antpress-css="${href}"]`)) return
          const link = document.createElement("link")
          link.rel = "stylesheet"
          link.href = href
          link.dataset.antpressCss = href
          document.head.appendChild(link)
        }

        const loadScript = src =>
          new Promise((resolve, reject) => {
            const found = document.querySelector(`script[data-antpress-js="${src}"]`)
            if (found) {
              if (found.dataset.loaded === "true") return resolve()
              found.addEventListener("load", () => resolve())
              found.addEventListener("error", () => reject(new Error(src)))
              return
            }

            const el = document.createElement("script")
            el.src = src
            el.async = false
            el.dataset.antpressJs = src
            el.addEventListener("load", () => {
              el.dataset.loaded = "true"
              resolve()
            })
            el.addEventListener("error", () => reject(new Error(src)))
            document.head.appendChild(el)
          })

        const loadEditor = data => {
          if (!loading) {
            loadCss(data.editorCss)
            loadCss(data.editorDarkCss)
            // i18n は Editor 本体に依存するので順番を守る
            loading = loadScript(data.editorJs).then(() => loadScript(data.editorI18n))
          }
          return loading
        }

        export default {
          async mounted() {
            this.bodyInput = this.el.querySelector('input[name="article[body]"]')
            this.formatInput = this.el.querySelector('input[name="article[body_format]"]')
            const uploadPath = this.el.dataset.uploadPath
            const csrfToken = document
              .querySelector("meta[name='csrf-token']")
              .getAttribute("content")

            let Editor
            try {
              await loadEditor(this.el.dataset)
              Editor = window.toastui && window.toastui.Editor
              if (!Editor) throw new Error("window.toastui.Editor が未定義")
            } catch (error) {
              console.error("Toast UI Editor の読み込みに失敗しました", error)
              this.el.querySelector("#article-editor-root").textContent =
                "エディタの読み込みに失敗しました。ページを再読み込みしてください。"
              return
            }

            // 読み込み中に別画面へ移動していたら組み立てない
            if (this.unmounted) return

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
            this.unmounted = true
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
     # サムネイルは 1 枚なので max_entries: 1。
     # 上げたものをそのままサムネイルに設定する（→ handle_thumbnail_progress/3）
     |> allow_upload(:thumbnail,
       accept: Image.extensions(),
       max_entries: 1,
       max_file_size: Image.max_byte_size(),
       auto_upload: true,
       progress: &handle_thumbnail_progress/3
     )
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
      Blog.change_article(socket.assigns.current_user, socket.assigns.article, to_utc(attrs))

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  @impl true
  def handle_event("save", %{"article" => attrs}, socket) do
    save_article(socket, socket.assigns.live_action, to_utc(attrs))
  end

  @impl true
  def handle_event("open-picker", _params, socket) do
    {:noreply,
     socket
     |> assign(:images, Media.list_images(socket.assigns.current_user))
     |> assign(:picker_open?, true)}
  end

  # live_file_input はフォームの phx-change を要求する。
  # 検証は allow_upload と Media 側が行う
  @impl true
  def handle_event("validate-thumbnail-upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

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

  # アップロードが終わったらそのままサムネイルに設定してモーダルを閉じる。
  # 「サムネイルを選ぶ」ために開いたモーダルなので、上げた画像を使う意図は明確
  defp handle_thumbnail_progress(:thumbnail, entry, socket) do
    if entry.done? do
      scope = socket.assigns.current_user

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Media.create_image(scope, %{filename: entry.client_name, body: File.read!(path)})}
        end)

      case result do
        {:ok, image} ->
          {:noreply,
           socket
           |> assign(:thumbnail, image)
           |> assign(:images, Media.list_images(scope))
           |> assign(:picker_open?, false)
           |> put_form_change(:thumbnail_image_id, image.id)
           |> put_flash(:info, "画像をアップロードしてサムネイルに設定しました")}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "#{entry.client_name}: #{MediaError.message(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  defp upload_error_message(:too_large),
    do: "ファイルサイズが上限を超えています（#{div(Image.max_byte_size(), 1_000_000)}MB まで）"

  defp upload_error_message(:not_accepted),
    do: "対応していない画像形式です（JPEG / PNG / GIF / WebP）"

  defp upload_error_message(:too_many_files), do: "一度にアップロードできるのは 1 件までです"
  defp upload_error_message(other), do: "アップロードに失敗しました（#{inspect(other)}）"

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

  # ⚠️ datetime-local はタイムゾーンを持たない。日本時間として入力された
  # 値を UTC に直してから changeset に渡す（→ AntPressWeb.JST）
  defp to_utc(attrs), do: JST.shift_params(attrs, ["published_at"])

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
    |> assign(:editor_format, to_string(article.body_format || :rich_text))
  end

  # body_format と Toast UI の initialEditType の対応（→ Article の説明）。
  # 既定は WYSIWYG（Markdown は玄人向け）
  defp editor_mode("markdown"), do: "markdown"
  defp editor_mode(_rich_text), do: "wysiwyg"

  defp category_options(scope) do
    Enum.map(Blog.list_blog_categories(scope), &{&1.name, &1.id})
  end
end
