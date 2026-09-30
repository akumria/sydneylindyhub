# frozen_string_literal: true

require File.expand_path("config/application", __dir__)

if Rails.env.local?
  require "rubocop/rake_task"
  RuboCop::RakeTask.new

  task lint_styles: :environment do
    system("yarn stylelint") || exit($CHILD_STATUS.exitstatus)
  end

  task erb_lint: :environment do
    system("bundle exec erb_lint --lint-all") || exit($CHILD_STATUS.exitstatus)
  end

  # The browser-driven system specs load the compiled assets, so build them
  # before the specs rather than trusting whatever was last compiled.
  # jsbundling-rails already does this for JavaScript, by hanging
  # javascript:build off spec:prepare, but nothing does it for Sass.
  task default: %i[dartsass:build spec rubocop erb_lint lint_styles]
end

Swingoutlondon::Application.load_tasks
