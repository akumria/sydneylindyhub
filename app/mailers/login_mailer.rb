# frozen_string_literal: true

# Sends short-lived sign-in links to approved editors.
class LoginMailer < ApplicationMailer
  def magic_link(role)
    @role = role
    @token = EditorLoginToken.generate(role)
    mail(to: role.email, subject: "Your #{tc('site_name')} editor sign-in link")
  end
end
