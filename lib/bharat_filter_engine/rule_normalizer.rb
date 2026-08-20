# frozen_string_literal: true

module BharatFilterEngine
  class RuleNormalizer
    def self.call(rule)
      return nil unless rule

      rule = rule.transform_keys(&:to_sym)

      return rule if rule[:filter_type].present?

      # Legacy configuration support.
      #
      # Old:
      # {
      #   type: :string,
      #   dbcolumn: :stage
      # }
      #
      # New:
      # {
      #   type: :single,
      #   filter_type: :string,
      #   dbcolumn: :stage
      # }

      scope_type =
        if rule[:type] == :nested
          :nested
        else
          :single
        end

      filter_type =
        if rule[:type] == :nested
          rule[:filter_type]
        else
          rule[:type]
        end

      rule.merge(
        type: scope_type,
        filter_type: filter_type
      )
    end
  end
end