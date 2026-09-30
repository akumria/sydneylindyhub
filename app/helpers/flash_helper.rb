# frozen_string_literal: true

module FlashHelper
  # The Stimulus flash controller fades the message out a few seconds after the
  # page loads, which is what we want for a real visitor. The browser specs
  # assert that a flash is visible immediately after submitting a form, so in
  # the test environment the flash is left in place: asserting on it would
  # otherwise race the timer and fail intermittently.
  def flash_data_attributes
    Rails.env.test? ? {} : { controller: "flash" }
  end
end
