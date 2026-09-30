# frozen_string_literal: true

class EditorLoginToken
  PURPOSE = "editor-login"
  LIFETIME = 15.minutes

  def self.generate(role)
    verifier.generate(role.email, expires_in: LIFETIME, purpose: PURPOSE)
  end

  def self.role_for(token)
    email = verifier.verify(token, purpose: PURPOSE)
    Role.find_by(email: email.to_s.downcase)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end
  private_class_method :verifier
end
