# frozen_string_literal: true

module BharatFilterEngine
  class RuleNormalizer
    KNOWN_FILTER_TYPES = %i[
      string
      array
      boolean
      integer
      float
      daterange
      search
      presence
    ].freeze

    KNOWN_RANGE_TYPES = %i[gte lte between].freeze
    NUMERIC_FILTER_TYPES = %i[integer float].freeze
    NEGATE_UNSUPPORTED_FILTER_TYPES = %i[daterange search presence].freeze

    def self.call(rule)
      return nil unless rule

      normalized = normalize(rule.transform_keys(&:to_sym))
      validate!(normalized)
      normalized
    end

    def self.normalize(rule)
      return rule if rule[:filter_type].present?

      scope_type = rule[:type] == :nested ? :nested : :single
      filter_type = rule[:type] == :nested ? rule[:filter_type] : rule[:type]

      rule.merge(
        type: scope_type,
        filter_type: filter_type
      )
    end
    private_class_method :normalize

    def self.validate!(rule)
      filter_type = rule[:filter_type]

      unless KNOWN_FILTER_TYPES.include?(filter_type)
        raise InvalidConfigurationError,
              "BharatFilterEngine: unknown filter_type #{filter_type.inspect}. " \
              "Expected one of #{KNOWN_FILTER_TYPES.inspect}."
      end

      if rule[:type] == :nested && rule[:association].blank?
        raise InvalidConfigurationError,
              'BharatFilterEngine: a `type: :nested` filter rule requires ' \
              'an `association:` key.'
      end

      if rule[:type] == :nested && filter_type == :search
        raise InvalidConfigurationError,
              'BharatFilterEngine: `filter_type: :search` does not support ' \
              '`type: :nested` -- use `__` notation inside `dbcolumns:` instead.'
      end

      if filter_type == :search
        if Array(rule[:dbcolumns]).empty?
          raise InvalidConfigurationError,
                'BharatFilterEngine: a `filter_type: :search` rule requires ' \
                'a non-empty `dbcolumns:` array.'
        end
      elsif rule[:dbcolumn].blank?
        raise InvalidConfigurationError,
              'BharatFilterEngine: filter rule requires a `dbcolumn:` key.'
      end

      validate_range_type!(rule, filter_type)
      validate_negate!(rule, filter_type)
    end
    private_class_method :validate!

    def self.validate_range_type!(rule, filter_type)
      return unless rule[:range_type]

      unless KNOWN_RANGE_TYPES.include?(rule[:range_type])
        raise InvalidConfigurationError,
              "BharatFilterEngine: unknown range_type #{rule[:range_type].inspect}. " \
              "Expected one of #{KNOWN_RANGE_TYPES.inspect}."
      end

      return if NUMERIC_FILTER_TYPES.include?(filter_type)

      raise InvalidConfigurationError,
            'BharatFilterEngine: `range_type:` is only supported for ' \
            "#{NUMERIC_FILTER_TYPES.inspect} filters, got #{filter_type.inspect}."
    end
    private_class_method :validate_range_type!

    def self.validate_negate!(rule, filter_type)
      return unless rule[:negate]
      return if rule[:range_type].blank? && !NEGATE_UNSUPPORTED_FILTER_TYPES.include?(filter_type)

      raise InvalidConfigurationError,
            'BharatFilterEngine: `negate: true` is not supported together ' \
            "with `range_type:`, or with #{NEGATE_UNSUPPORTED_FILTER_TYPES.inspect} filters."
    end
    private_class_method :validate_negate!
  end
end
