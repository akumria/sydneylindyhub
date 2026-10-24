# frozen_string_literal: true

# Base class for all mailers
class ApplicationMailer < ActionMailer::Base
  include CityHelper

  default from: -> { tc("email_address") }
  layout "mailer"

  def default_url_options
    return super if ENV["EDITORIAL_HOST"].blank?

    super.except(:port).merge(host: ENV.fetch("EDITORIAL_HOST"), protocol: "https")
  end
end
