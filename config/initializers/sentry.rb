# frozen_string_literal: true

require "active_support/parameter_filter"

Sentry.init do |config|
  config.dsn = Rails.application.credentials.sentry
  config.send_default_pii = true
  config.breadcrumbs_logger = %i[sentry_logger active_support_logger http_logger]

  filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  config.before_send = lambda do |event, _hint|
    filter.filter(event.to_hash)
  end
end
