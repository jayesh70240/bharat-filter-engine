# frozen_string_literal: true

module BharatFilterEngine
  class DynamicFilterValues
    def initialize(scope:, model: nil, field:)
      @scope = scope
      @model = model || scope.klass
      @field = field.to_s
    end

    def call
      resolver = AssociationResolver.new(@scope)

      result = resolver.resolve_column(@field)
      return nil unless result

      scoped =
        resolver.join(
          @scope,
          result[:associations]
        )

      column = result[:column]
      nested = result[:associations].present?

      not_condition =
        nested ? { result[:table_name] => { column => [nil, ""] } } : { column => [nil, ""] }

      qualified_column =
        nested ? Arel.sql("#{result[:table_name]}.#{column}") : column

      scoped
        .where.not(not_condition)
        .distinct
        .order(qualified_column)
        .pluck(qualified_column)
    end
  end
end
