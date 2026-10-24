# frozen_string_literal: true

# Base class for all mailers
class ApplicationMailer < ActionMailer::Base
  include CityHelper

  default from: -> { tc("email_address") }, "Auto-Submitted" => "auto-generated"
  layout "mailer"

  def default_url_options
    super.except(:port).merge(UrlHelpers.new.default_url_options)
  end
end
