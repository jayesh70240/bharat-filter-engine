# frozen_string_literal: true

module BharatFilterEngine
  class Engine

    class << self

      def apply(scope:, config:, params:)
        new(
          scope,
          config,
          params
        ).call
      end

      def filter_values(scope:, config:, params:)
        field =
          params[:filter_field] ||
          params["filter_field"]

        rule =
          config[field&.to_sym]

        rule =
          RuleNormalizer.call(rule)

        return [] unless rule&.dig(:dbcolumn)

        field_name =
          if rule[:association]
            "#{rule[:association]}__#{rule[:dbcolumn]}"
          else
            rule[:dbcolumn].to_s
          end

        DynamicFilterValues.new(
          scope: scope,
          field: field_name
        ).call || []
      end

    end

    def initialize(scope, config = {}, params = {})
        @scope = scope
        @config = config || {}
        @params = normalize_params(params)
    end

    def call
      scope = @scope

      @config.each do |key, raw_rule|

        value =
          @params[key.to_sym]

        next if value.blank? && value != false

        rule =
          RuleNormalizer.call(raw_rule)

        next unless rule

        scope =
          apply_rule(
            scope,
            rule,
            value
          )
      end

      scope
    end

    private

    def apply_rule(scope, rule, value)
      case rule[:type]
      when :nested
        apply_nested_filter(
          scope,
          rule,
          value
        )
      else
        apply_filter_by_type(
          scope,
          rule,
          value
        )
      end
    end

    def apply_nested_filter(scope, rule, value)
      association =
        rule[:association]

      resolver =
        AssociationResolver.new(scope)

      result =
        resolver.resolve(
          association
        )

      return scope unless result

      joined_scope =
        resolver.join(
          scope,
          result[:associations]
        )

      apply_filter_by_type(
        joined_scope,
        rule,
        value,
        table_name: result[:table_name]
      ).distinct
    end

    def apply_filter_by_type(
      scope,
      rule,
      value,
      table_name: nil
    )

      column =
        rule[:dbcolumn]

      case rule[:filter_type]

      when :array
        apply_array_filter(
          scope,
          column,
          value,
          table_name
        )

      when :boolean
        apply_boolean_filter(
          scope,
          column,
          value,
          table_name
        )

      when :integer
        apply_numeric_filter(
          scope,
          rule,
          value.to_i,
          table_name: table_name
        )

      when :float
        apply_numeric_filter(
          scope,
          rule,
          value.to_f,
          table_name: table_name
        )

      when :string
        apply_string_filter(
          scope,
          column,
          value,
          table_name
        )

      when :daterange
        apply_date_range_filter(
          scope,
          rule,
          value,
          table_name: table_name
        )

      when :search
        SearchBuilder.new(
          scope: scope,
          allowed_columns: rule[:dbcolumns]
        ).apply(value)

      else
        scope
      end
    end

    def apply_array_filter(
      scope,
      column,
      value,
      table_name
    )

      apply_condition(
        scope,
        column,
        Array(value),
        table_name
      )
    end

    def apply_boolean_filter(
      scope,
      column,
      value,
      table_name
    )

      cast_value =
        ActiveModel::Type::Boolean
          .new
          .cast(value)

      apply_condition(
        scope,
        column,
        cast_value,
        table_name
      )
    end

    def apply_string_filter(
      scope,
      column,
      value,
      table_name
    )

      apply_condition(
        scope,
        column,
        value,
        table_name
      )
    end

    # Shared by array/boolean/string/exact-numeric filters: applies a
    # plain equality (or IN, for arrays) condition, qualifying it by
    # table_name when the filter comes from a joined association.
    def apply_condition(scope, column, value, table_name)
      if table_name
        scope.where(
          table_name => {
            column => value
          }
        )
      else
        scope.where(
          column => value
        )
      end
    end

    def apply_numeric_filter(
      scope,
      rule,
      value,
      table_name: nil
    )

      column =
        rule[:dbcolumn]

      qualified_column =
        if table_name
          "#{table_name}.#{column}"
        else
          column.to_s
        end

      case rule[:range_type]

      when :gte

        scope.where(
          "#{qualified_column} >= ?",
          value
        )

      when :lte

        scope.where(
          "#{qualified_column} <= ?",
          value
        )

      else
        apply_condition(
          scope,
          column,
          value,
          table_name
        )
      end
    end

    def apply_date_range_filter(
      scope,
      rule,
      value,
      table_name: nil
    )

      return scope unless value.present?

      column =
        rule[:dbcolumn]

      qualified_column =
        if table_name
          "#{table_name}.#{column}"
        else
          column.to_s
        end

      from, to =
        case value

        when Hash
          [
            value[:from] ||
              value["from"],

            value[:to] ||
              value["to"]
          ]

        when Array
          value

        when String
          value
            .split(",")
            .map(&:strip)

        end

      return scope unless
        from.present? || to.present?

      from =
        normalize_date(
          from,
          :start
        ) if from.present?

      to =
        normalize_date(
          to,
          :end
        ) if to.present?

      if from.present? && to.present?

        scope.where(
          qualified_column => from..to
        )

      elsif from.present?

        scope.where(
          "#{qualified_column} >= ?",
          from
        )

      else

        scope.where(
          "#{qualified_column} <= ?",
          to
        )
      end
    end

    def normalize_date(value, boundary)
      return value if
        value.is_a?(Time) ||
        value.is_a?(ActiveSupport::TimeWithZone)

      date =
        Date.parse(
          value.to_s
        )

      if boundary == :start
        date.beginning_of_day
      else
        date.end_of_day
      end
    end

    def normalize_params(params)
      deep_normalize_params(
        params.to_h.deep_symbolize_keys
      )
    end

    def deep_normalize_params(params)
      params.transform_values do |value|

        if value.is_a?(Hash)
          deep_normalize_params(value)
        else
          normalize_value(value)
        end

      end
    end

    def normalize_value(value)
      return value if value.is_a?(Array)
      return value unless value.is_a?(String)

      stripped =
        value.strip

      if stripped.start_with?("[")
        begin
          JSON.parse(stripped)
        rescue JSON::ParserError
          value
        end

      elsif value.include?(",")

        value
          .split(",")
          .map(&:strip)

      else

        value
      end
    end
  end
end