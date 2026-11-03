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
          params['filter_field']

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

        term =
          params[:filter_term] ||
          params['filter_term']

        limit =
          params[:filter_limit] ||
          params['filter_limit']

        DynamicFilterValues.new(
          scope: scope,
          field: field_name,
          term: term,
          limit: limit
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

      unless result
        raise InvalidAssociationError,
              'BharatFilterEngine: could not resolve association ' \
              "#{association.inspect} configured for filter " \
              "#{rule[:dbcolumn].inspect}. Check the `association:` key " \
              'in your filter config.'
      end

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
          table_name,
          negate: rule[:negate]
        )

      when :boolean
        apply_boolean_filter(
          scope,
          column,
          value,
          table_name,
          negate: rule[:negate]
        )

      when :integer
        apply_numeric_filter(
          scope,
          rule,
          value,
          :to_i,
          table_name: table_name
        )

      when :float
        apply_numeric_filter(
          scope,
          rule,
          value,
          :to_f,
          table_name: table_name
        )

      when :string
        apply_string_filter(
          scope,
          column,
          value,
          table_name,
          negate: rule[:negate]
        )

      when :daterange
        apply_date_range_filter(
          scope,
          rule,
          value,
          table_name: table_name
        )

      when :presence
        apply_presence_filter(
          scope,
          column,
          value,
          table_name
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
      table_name,
      negate: false
    )
      apply_condition(
        scope,
        column,
        Array(value),
        table_name,
        negate: negate
      )
    end

    def apply_boolean_filter(
      scope,
      column,
      value,
      table_name,
      negate: false
    )
      cast_value =
        ActiveModel::Type::Boolean
        .new
        .cast(value)

      apply_condition(
        scope,
        column,
        cast_value,
        table_name,
        negate: negate
      )
    end

    def apply_string_filter(
      scope,
      column,
      value,
      table_name,
      negate: false
    )
      apply_condition(
        scope,
        column,
        value,
        table_name,
        negate: negate
      )
    end

    def apply_presence_filter(scope, column, value, table_name)
      present = ActiveModel::Type::Boolean.new.cast(value)

      arel_column =
        if table_name
          Arel::Table.new(table_name)[column]
        else
          scope.klass.arel_table[column]
        end

      if present
        scope.where(
          arel_column.not_eq(nil).and(
            arel_column.not_eq('')
          )
        )
      else
        scope.where(
          arel_column.eq(nil).or(
            arel_column.eq('')
          )
        )
      end
    end

    def apply_condition(scope, column, value, table_name, negate: false)
      if negate && value.is_a?(Array)
        return apply_negated_array_condition(
          scope,
          column,
          value,
          table_name
        )
      end

      condition =
        if table_name
          { table_name => { column => value } }
        else
          { column => value }
        end

      negate ? scope.where.not(condition) : scope.where(condition)
    end

    def apply_negated_array_condition(scope, column, values, table_name)
      arel_column =
        if table_name
          Arel::Table.new(table_name)[column]
        else
          scope.klass.arel_table[column]
        end

      membership = arel_column.in(values.compact)

      predicate =
        if values.include?(nil)
          arel_column.eq(nil).or(membership)
        else
          membership
        end

      scope.where(Arel::Nodes::Not.new(predicate))
    end

    NUMERIC_PATTERN = /\A[+-]?\d+(\.\d+)?\z/

    def apply_numeric_filter(
      scope,
      rule,
      value,
      caster,
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
        return scope unless numeric_string?(value)

        scope.where("#{qualified_column} >= ?", cast_numeric(value, caster))

      when :lte
        return scope unless numeric_string?(value)

        scope.where("#{qualified_column} <= ?", cast_numeric(value, caster))

      when :between
        apply_numeric_between(
          scope,
          qualified_column,
          value,
          caster
        )

      else
        return scope unless numeric_string?(value)

        apply_condition(
          scope,
          column,
          cast_numeric(value, caster),
          table_name,
          negate: rule[:negate]
        )
      end
    end

    def apply_numeric_between(scope, qualified_column, value, caster)
      return scope unless value.present?

      raw_from, raw_to =
        extract_bounds(value)

      return scope unless
        raw_from.present? || raw_to.present?

      if raw_from.present? && numeric_string?(raw_from)
        from =
          cast_numeric(raw_from, caster)
      end

      if raw_to.present? && numeric_string?(raw_to)
        to =
          cast_numeric(raw_to, caster)
      end

      return scope unless from || to

      if from && to
        scope.where(qualified_column => from..to)
      elsif from
        scope.where("#{qualified_column} >= ?", from)
      else
        scope.where("#{qualified_column} <= ?", to)
      end
    end

    def numeric_string?(value)
      value.to_s.strip.match?(NUMERIC_PATTERN)
    end

    def cast_numeric(value, caster)
      value.to_s.public_send(caster)
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

      raw_from, raw_to =
        extract_bounds(value)

      return scope unless
        raw_from.present? || raw_to.present?

      if raw_from.present?
        from =
          normalize_date(
            raw_from,
            :start
          )
      end

      if raw_to.present?
        to =
          normalize_date(
            raw_to,
            :end
          )
      end

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

    def extract_bounds(value)
      case value

      when Hash
        [
          value[:from] || value['from'],
          value[:to] || value['to']
        ]

      when Array
        value

      when String
        value
          .split(',')
          .map(&:strip)

      else
        [nil, nil]
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

      if stripped.start_with?('[')
        begin
          JSON.parse(stripped)
        rescue JSON::ParserError
          value
        end

      elsif value.include?(',')

        value
          .split(',')
          .map(&:strip)

      else

        value
      end
    end
  end
end
