# frozen_string_literal: true

class StaticPublication < ApplicationRecord
  validates :status, inclusion: { in: %w[queued running succeeded failed] }
  validates :requested_by, presence: true

  scope :active, -> { where(status: %w[queued running]) }

  def self.github?
    ENV["STATIC_PUBLISH_BACKEND"] == "github"
  end

  def self.enabled?
    ENV["STATIC_PUBLISH_ENABLED"] == "true" && (!github? || GithubPublication.configured?)
  end
end
