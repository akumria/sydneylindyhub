# frozen_string_literal: true

class Role < ApplicationRecord
  ROLES = [
    ADMIN = "admin",
    EDITOR = "editor"
  ].freeze
  enum :role, {
    admin: ADMIN,
    editor: EDITOR
  }

  normalizes :email, with: -> { it.strip.downcase }
  validates :email, presence: true, email: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validates :role, presence: true
end
