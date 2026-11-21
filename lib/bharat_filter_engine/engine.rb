# frozen_string_literal: true

module BharatFilterEngine
  class Engine
    INTEGER_PATTERN = /\A[+-]?\d+\z/
    NUMERIC_PATTERN = /\A[+-]?\d+(\.\d+)?\z/
    GROUPED_INTEGER_PATTERN =
      /\A[+-]?(?:\d{1,3}(?:,\d{3})+|\d{1,3}(?:,\d{2})*,\d{3})\z/
    GROUPED_NUMERIC_PATTERN =
      /\A[+-]?(?:\d{1,3}(?:,\d{3})+|\d{1,3}(?:,\d{2})*,\d{3})(?:\.\d+)?\z/
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
      @tracker = JoinTracker.new(scope.klass)
      @subquery_groups = {}

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

      @subquery_groups.each_value do |group|
        scope = apply_subquery_group(scope, group)
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

      if @tracker.claim(result) == :subquery
        group =
          (@subquery_groups[result[:associations]] ||= {
            result: result,
            entries: []
          })

        group[:entries] << [rule, value]

        return scope
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
        table_name: result[:table_name],
        klass: result[:klass]
      ).distinct
    end

    def apply_subquery_group(scope, group)
      result = group[:result]

      subquery =
        AssociationResolver.new(scope).subquery(result[:associations]) do |relation|
          group[:entries].reduce(relation) do |current, (rule, value)|
            apply_filter_by_type(
              current,
              rule,
              value,
              table_name: result[:table_name],
              klass: result[:klass]
            )
          end
        end

      scope.where(scope.klass.primary_key => subquery)
    end

    def apply_filter_by_type(
      scope,
      rule,
      value,
      table_name: nil,
      klass: nil
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
          table_name,
          klass: klass
        )

      when :search
        SearchBuilder.new(
          scope: scope,
          allowed_columns: rule[:dbcolumns],
          tracker: @tracker
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
        Array(normalize_array_value(value)),
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

    def apply_string_filter(scope,column,value,table_name,negate: false)
      apply_condition(scope,column,value,table_name,negate: negate)
    end

    def apply_presence_filter(scope, column, value, table_name, klass: nil)
      present = ActiveModel::Type::Boolean.new.cast(value)
      klass ||= scope.klass
      arel_column =
        if table_name
          Arel::Table.new(table_name)[column]
        else
          klass.arel_table[column]
        end

      if present
        scope.where(ColumnHelper.present_predicate(arel_column, klass, column))
      else
        scope.where(ColumnHelper.blank_predicate(arel_column, klass, column))
      end
    end

    def apply_condition(scope, column, value, table_name, negate: false)
      if negate && value.is_a?(Array)
        return apply_negated_array_condition(scope,column,value,table_name)
      end

      if negate
        return scope.where(null_inclusive_negation(scope,column,value,table_name))
      end

      condition =
        if table_name
          { table_name => { column => value } }
        else
          { column => value }
        end

      scope.where(condition)
    end

    def apply_negated_array_condition(scope, column, values, table_name)
      arel_column = filter_arel_column(scope, column, table_name)
      membership = arel_column.in(values.compact)
      return scope.where(Arel::Nodes::Not.new(arel_column.eq(nil).or(membership))) if values.include?(nil)
      scope.where(arel_column.eq(nil).or(Arel::Nodes::Not.new(membership)))
    end

    def null_inclusive_negation(scope, column, value, table_name)
      arel_column = filter_arel_column(scope, column, table_name)
      arel_column.eq(nil).or(arel_column.not_eq(value))
    end

    def filter_arel_column(scope, column, table_name)
      if table_name
        Arel::Table.new(table_name)[column]
      else
        scope.klass.arel_table[column]
      end
    end

    def normalize_array_value(value)
      return value unless value.is_a?(String)
      stripped = value.strip
      if stripped.start_with?('[')
        parse_json_array(stripped) || value
      elsif value.include?(',')
        value.split(',').map(&:strip)
      else
        value
      end
    end

    def parse_json_array(value)
      parsed = JSON.parse(value)
      parsed if parsed.is_a?(Array)
    rescue JSON::ParserError
      nil
    end

    def apply_numeric_filter(scope,rule,value,caster,table_name: nil)
      column = rule[:dbcolumn]

      qualified_column =
        if table_name
          "#{table_name}.#{column}"
        else
          column.to_s
        end

      case rule[:range_type]

      when :gte
        return scope unless numeric_string?(value, caster)
        scope.where("#{qualified_column} >= ?", cast_numeric(value, caster))

      when :lte
        return scope unless numeric_string?(value, caster)
        scope.where("#{qualified_column} <= ?", cast_numeric(value, caster))

      when :between
        apply_numeric_between(scope,qualified_column,value,caster)

      else
        values = exact_numeric_values(value, caster)

        return scope unless values
        apply_condition(scope,column,values.one? ? values.first : values,table_name,negate: rule[:negate])
      end
    end

    def exact_numeric_values(value, caster)
      values =
        case value
        when Array
          value
        when String
          numeric_string?(value, caster) ? [value] : value.split(',').map(&:strip)
        else
          [value]
        end

      return unless values.all? { |entry| numeric_string?(entry, caster) }
      values.map { |entry| cast_numeric(entry, caster) }
    end

    def apply_numeric_between(scope, qualified_column, value, caster)
      return scope unless value.present?

      raw_from, raw_to = extract_bounds(value)

      return scope unless
        raw_from.present? || raw_to.present?

      if raw_from.present? && numeric_string?(raw_from, caster)
        from = cast_numeric(raw_from, caster)
      end

      if raw_to.present? && numeric_string?(raw_to, caster)
        to = cast_numeric(raw_to, caster)
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

    def numeric_string?(value, caster)
      !normalized_numeric_string(value, caster).nil?
    end

    def cast_numeric(value, caster)
      normalized_numeric_string(value, caster).public_send(caster)
    end

    def normalized_numeric_string(value, caster)
      numeric = value.to_s.strip
      plain_pattern, grouped_pattern = numeric_patterns(caster)

      return numeric if numeric.match?(plain_pattern)
      return numeric.delete(',') if numeric.match?(grouped_pattern)

      nil
    end

    def numeric_patterns(caster)
      if caster == :to_i
        [INTEGER_PATTERN, GROUPED_INTEGER_PATTERN]
      else
        [NUMERIC_PATTERN, GROUPED_NUMERIC_PATTERN]
      end
    end

    def apply_date_range_filter(scope,rule,value,table_name: nil)
      return scope unless value.present?

      column = rule[:dbcolumn]

      qualified_column =
        if table_name
          "#{table_name}.#{column}"
        else
          column.to_s
        end

      raw_from, raw_to = extract_bounds(value)

      return scope unless
        raw_from.present? || raw_to.present?

      if raw_from.present?
        from = normalize_date(raw_from,:start)
      end

      if raw_to.present?
        to = normalize_date(raw_to,:end)
      end

      if from.present? && to.present?
        scope.where(qualified_column => from..to)

      elsif from.present?
        scope.where("#{qualified_column} >= ?",from)

      else
        scope.where("#{qualified_column} <= ?",to)
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
        value.split(',').map(&:strip)

      else
        [nil, nil]
      end
    end

    def normalize_date(value, boundary)
      return value if
        value.is_a?(Time) ||
        value.is_a?(ActiveSupport::TimeWithZone)

      date = Date.parse(value.to_s)

      if boundary == :start
        date.beginning_of_day
      else
        date.end_of_day
      end
    rescue Date::Error
      raise InvalidFilterError, "BharatFilterEngine: invalid date #{value.inspect}."
    end

    def normalize_params(params)
      params.to_h.deep_symbolize_keys
    end
  end
end
