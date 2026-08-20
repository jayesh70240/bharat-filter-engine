# frozen_string_literal: true

require "active_record"
require "active_model"
require "active_support"
require "json"

require_relative "bharat_filter_engine/version"
require_relative "bharat_filter_engine/errors"
require_relative "bharat_filter_engine/association_resolver"
require_relative "bharat_filter_engine/rule_normalizer"
require_relative "bharat_filter_engine/search_builder"
require_relative "bharat_filter_engine/dynamic_filter_values"
require_relative "bharat_filter_engine/engine"

module BharatFilterEngine
  class << self
    def apply(scope:, config:, params:)
      Engine.apply(
        scope: scope,
        config: config,
        params: params
      )
    end

    def filter_values(scope:, config:, params:)
      Engine.filter_values(
        scope: scope,
        config: config,
        params: params
      )
    end
  end
end