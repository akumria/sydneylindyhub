# frozen_string_literal: true

# Days of the week starting Monday
DAYNAMES = Date::DAYNAMES.rotate

default_donate_link = "https://ko-fi.com/sydneylindyhub" if ENV.fetch("CITY", "sydney") == "sydney"
Rails.application.config.x.donate_link = ENV.fetch("DONATE_LINK", default_donate_link)
