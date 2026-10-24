# frozen_string_literal: true

# Claims persisted work atomically; interrupted requests require maintainer review.
class StaticPublicationWorker
  def initialize(runner: StaticPublicationRunner.new)
    @runner = runner
  end

  def run_once
    return unless StaticPublication.enabled?
    return if StaticPublication.github?

    publication = claim
    return unless publication

    publication.update!(status: publish(publication) ? "succeeded" : "failed", finished_at: Time.current)
    publication
  end

  private

  def publish(publication)
    @runner.call(publication)
  rescue StandardError => e
    Rails.logger.error("Static publication #{publication.id} failed: #{e.class}")
    false
  end

  def claim
    StaticPublication.transaction do
      publication = StaticPublication.where(status: "queued").lock.first
      publication&.update!(status: "running", started_at: Time.current)
      publication
    end
  end
end
