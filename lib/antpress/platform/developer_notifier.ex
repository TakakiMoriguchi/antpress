defmodule AntPress.Platform.DeveloperNotifier do
  import Swoosh.Email

  alias AntPress.Mailer
  alias AntPress.Platform.Developer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"AntPress", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a developer email.
  """
  def deliver_update_email_instructions(developer, url) do
    deliver(developer.email, "Update email instructions", """

    ==============================

    Hi #{developer.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(developer, url) do
    case developer do
      %Developer{confirmed_at: nil} -> deliver_confirmation_instructions(developer, url)
      _ -> deliver_magic_link_instructions(developer, url)
    end
  end

  defp deliver_magic_link_instructions(developer, url) do
    deliver(developer.email, "Log in instructions", """

    ==============================

    Hi #{developer.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(developer, url) do
    deliver(developer.email, "Confirmation instructions", """

    ==============================

    Hi #{developer.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
