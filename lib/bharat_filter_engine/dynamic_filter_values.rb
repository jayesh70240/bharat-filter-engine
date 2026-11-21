# frozen_string_literal: true

module BharatFilterEngine
  class DynamicFilterValues
    LIKE_ESCAPE_CHAR = '\\'
    MAX_LIMIT = 100

    def initialize(scope:, field:, model: nil, term: nil, limit: nil)
      @scope = scope
      @model = model || scope.klass
      @field = field.to_s
      @term = term.presence
      @limit = normalize_limit(limit)
    end

    def call
      resolver = AssociationResolver.new(@scope)

      result = resolver.resolve_column(@field)
      return nil unless result

      scoped = resolver.join(@scope, result[:associations])
      arel_column = result[:klass].arel_table[result[:column]]
      scoped = scoped.where(ColumnHelper.present_predicate(arel_column, result[:klass], result[:column]))
      scoped = apply_term(scoped, arel_column) if @term
      scoped = scoped.distinct.order(arel_column)
      scoped = scoped.limit(@limit)

      scoped.pluck(arel_column)
    end

    private

    def apply_term(scoped, arel_column)
      escaped = @term.to_s.gsub(/[\\%_]/) { |char| "#{LIKE_ESCAPE_CHAR}#{char}" }
      scoped.where(arel_column.matches("%#{escaped}%", LIKE_ESCAPE_CHAR))
    end

    def normalize_limit(limit)
      parsed_limit = Integer(limit, exception: false)
      return MAX_LIMIT unless parsed_limit&.positive?
      [parsed_limit, MAX_LIMIT].min
    end
  end
end
