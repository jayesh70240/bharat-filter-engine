# frozen_string_literal: true

module BharatFilterEngine
  class DynamicFilterValues
    LIKE_ESCAPE_CHAR = "\\"

    def initialize(scope:, model: nil, field:, term: nil, limit: nil)
      @scope = scope
      @model = model || scope.klass
      @field = field.to_s
      @term = term.presence
      @limit = limit.presence&.to_i
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

      arel_column = result[:klass].arel_table[result[:column]]

      scoped =
        scoped.where(
          arel_column.not_eq(nil).and(
            arel_column.not_eq("")
          )
        )

      scoped = apply_term(scoped, arel_column) if @term

      scoped = scoped.distinct.order(arel_column)
      scoped = scoped.limit(@limit) if @limit&.positive?

      scoped.pluck(arel_column)
    end

    private

    def apply_term(scoped, arel_column)
      escaped =
        @term.to_s.gsub(/[\\%_]/) { |char| "#{LIKE_ESCAPE_CHAR}#{char}" }

      scoped.where(
        arel_column.matches("%#{escaped}%", LIKE_ESCAPE_CHAR)
      )
    end
  end
end
