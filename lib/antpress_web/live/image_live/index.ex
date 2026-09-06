defmodule AntPressWeb.ImageLive.Index do
  @moduledoc """
  画像管理（→ `docs/SCREENS.md` C6）。

  アップロード・一覧・説明文（alt）の設定・削除を **1 画面**に収めている。
  カテゴリのように一覧／新規／編集を分けていないのは、画像の操作が
  「上げる」「alt を書く」「消す」しかなく、画面を移動する意味がないため。

  developer / admin 側には画像の画面を作らない。**記事の中身・画像・
  問い合わせ内容は developer から見えない**（→ `docs/SCREENS.md`）。
  """
  use AntPressWeb, :live_view

  alias AntPress.Media
  alias AntPressWeb.MediaError
  alias AntPress.Media.Image

  # 一度に選べる件数。ブラウザからの同時アップロードを増やしすぎない
  @max_entries 10

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        画像
        <:subtitle>
          記事や各ページで使う画像を管理します。JPEG / PNG / GIF / WebP、1 ファイル {@max_mb}MB まで。<br />
          「画像の説明」は任意ですが、入れておくと <strong>Google の画像検索</strong>で見つかりやすくなります。
          画像が表示できないときの代わりの文章にもなります。
        </:subtitle>
      </.header>

      <form id="image-upload" phx-change="validate" phx-submit="noop">
        <label
          class="flex flex-col items-center justify-center gap-2 rounded-lg border-2 border-dashed border-base-300 px-6 py-10 text-center cursor-pointer hover:border-primary hover:bg-base-200/40"
          phx-drop-target={@uploads.images.ref}
        >
          <.icon name="hero-arrow-up-tray" class="size-6 text-base-content/60" />
          <span class="font-medium">クリックして選択、またはここにドラッグ＆ドロップ</span>
          <span class="text-sm text-base-content/60">
            一度に {@max_entries} 件まで
          </span>
          <.live_file_input upload={@uploads.images} class="sr-only" />
        </label>
      </form>

      <div :for={err <- upload_errors(@uploads.images)} class="alert alert-error mt-4">
        {upload_error_message(err)}
      </div>

      <div :if={@uploads.images.entries != []} class="mt-4 space-y-2">
        <div :for={entry <- @uploads.images.entries} class="rounded-lg bg-base-200 p-3">
          <div class="flex items-center gap-3">
            <span class="flex-1 truncate text-sm">{entry.client_name}</span>
            <progress class="progress progress-primary w-32" value={entry.progress} max="100"></progress>
            <button
              type="button"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
              aria-label="アップロードを中止"
              class="btn btn-ghost btn-xs"
            >
              中止
            </button>
          </div>
          <p :for={err <- upload_errors(@uploads.images, entry)} class="mt-1 text-sm text-error">
            {upload_error_message(err)}
          </p>
        </div>
      </div>

      <p :if={@image_count == 0} class="mt-10 text-center text-base-content/60">
        まだ画像がありません。
      </p>

      <div
        id="images"
        phx-update="stream"
        class="mt-8 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4"
      >
        <div
          :for={{dom_id, image} <- @streams.images}
          id={dom_id}
          class="flex flex-col gap-2 rounded-lg border border-base-300 p-3"
        >
          <img
            src={Media.public_url(image)}
            alt={image.alt_text || ""}
            loading="lazy"
            class="aspect-square w-full rounded bg-base-200 object-contain"
          />

          <p class="truncate text-sm font-medium" title={image.filename}>{image.filename}</p>
          <p class="text-xs text-base-content/60">{meta_label(image)}</p>

          <%!-- ⚠️「代替テキスト」は専門用語なので画面には出さない
                （→ CLAUDE.md「画面に技術用語を出さない」） --%>
          <form phx-submit="save-alt">
            <input type="hidden" name="image_id" value={image.id} />
            <.field_label for={"image-alt-#{image.id}"}>画像の説明</.field_label>
            <div class="mt-1 flex items-center gap-1">
              <input
                type="text"
                id={"image-alt-#{image.id}"}
                name="alt_text"
                value={image.alt_text}
                maxlength="200"
                placeholder="例: 店舗の外観"
                class="input w-full"
              />
              <%!-- アイコンだけだと保存ボタンだと分からない（実際に分からなかった） --%>
              <.button>保存</.button>
            </div>
          </form>

          <div class="flex items-center justify-between text-sm">
            <button
              type="button"
              id={"copy-#{image.id}"}
              phx-hook=".CopyUrl"
              data-url={Media.public_url(image)}
              class="btn btn-ghost btn-xs"
            >
              URL をコピー
            </button>
            <.link
              phx-click={JS.push("delete", value: %{id: image.id})}
              data-confirm="この画像を削除します。記事で使っている場合は表示されなくなります。よろしいですか？"
              class="text-error"
            >
              削除
            </.link>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyUrl">
        export default {
          mounted() {
            this.el.addEventListener("click", async () => {
              // 開発環境の URL は "/uploads/..." と相対になる。
              // HP に貼るには絶対 URL が必要なので origin を補う
              const url = new URL(this.el.dataset.url, window.location.origin).href
              const label = this.el.textContent

              try {
                await navigator.clipboard.writeText(url)
                this.el.textContent = "コピーしました"
              } catch {
                this.el.textContent = "コピーできませんでした"
              }

              setTimeout(() => { this.el.textContent = label }, 1500)
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_user

    if connected?(socket) do
      Media.subscribe_images(scope)
    end

    images = Media.list_images(scope)

    {:ok,
     socket
     |> assign(:page_title, "画像")
     |> assign(:max_entries, @max_entries)
     |> assign(:max_mb, div(Image.max_byte_size(), 1_000_000))
     |> assign(:image_count, length(images))
     |> stream(:images, images)
     # auto_upload: ファイルを選んだ時点で送信を始める。
     # 素材置き場なので「選ぶ → 保存ボタン」の 2 手を踏ませる必要がない
     |> allow_upload(:images,
       accept: Image.extensions(),
       max_entries: @max_entries,
       max_file_size: Image.max_byte_size(),
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  # live_file_input はフォームの phx-change を要求する。
  # 検証は allow_upload と Media 側が行うのでここでは何もしない
  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  @impl true
  def handle_event("save-alt", %{"image_id" => id, "alt_text" => alt_text}, socket) do
    scope = socket.assigns.current_user
    image = Media.get_image!(scope, id)

    case Media.update_image(scope, image, %{alt_text: alt_text}) do
      {:ok, image} ->
        {:noreply,
         socket
         |> put_flash(:info, "画像の説明を保存しました")
         |> stream_insert(:images, image)}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, MediaError.message(changeset))}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_user
    image = Media.get_image!(scope, id)
    {:ok, _} = Media.delete_image(scope, image)

    {:noreply,
     socket
     |> put_flash(:info, "画像を削除しました")
     |> update(:image_count, &max(&1 - 1, 0))
     |> stream_delete(:images, image)}
  end

  @impl true
  def handle_info({type, %Image{}}, socket) when type in [:created, :updated, :deleted] do
    images = Media.list_images(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:image_count, length(images))
     |> stream(:images, images, reset: true)}
  end

  # entry.done? になった時点でファイルはサーバー側の一時ファイルに揃っている。
  # ⚠️ entry.client_type（ブラウザ申告の MIME）は渡さない。
  #    Media 側がバイナリから判定する（→ AntPress.Media.Probe）
  defp handle_progress(:images, entry, socket) do
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
           |> update(:image_count, &(&1 + 1))
           |> stream_insert(:images, image, at: 0)}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "#{entry.client_name}: #{MediaError.message(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end

  @doc """
  `allow_upload` が返すエラーを日本語に直す。テンプレートの
  `upload_errors/1,2` の結果を通す。

  ⚠️ 未知のエラーでも英語の atom がそのまま画面に出ないようにする。
  """
  def upload_error_message(:too_large),
    do: "ファイルサイズが上限を超えています（#{div(Image.max_byte_size(), 1_000_000)}MB まで）"

  def upload_error_message(:not_accepted),
    do: "対応していない画像形式です（JPEG / PNG / GIF / WebP）"

  def upload_error_message(:too_many_files),
    do: "一度にアップロードできるのは #{@max_entries} 件までです"

  def upload_error_message(other), do: "アップロードに失敗しました（#{inspect(other)}）"

  # 縦横サイズは読めないことがある（→ AntPress.Media.Probe）
  defp meta_label(%Image{width: w, height: h} = image) when is_integer(w) and is_integer(h),
    do: "#{w}×#{h} · #{byte_label(image.byte_size)}"

  defp meta_label(%Image{} = image), do: byte_label(image.byte_size)

  defp byte_label(bytes) when bytes >= 1_000_000,
    do: "#{Float.round(bytes / 1_000_000, 1)}MB"

  defp byte_label(bytes) when bytes >= 1_000, do: "#{div(bytes, 1_000)}KB"
  defp byte_label(bytes), do: "#{bytes}B"
end
