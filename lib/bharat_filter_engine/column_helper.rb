# frozen_string_literal: true

module BharatFilterEngine
  module ColumnHelper
    STRING_COLUMN_TYPES = %i[string text].freeze

    module_function

    def string_like?(klass, column)
      db_column = klass&.columns_hash&.[](column.to_s)
      db_column.nil? || STRING_COLUMN_TYPES.include?(db_column.type)
    end

    def present_predicate(arel_column, klass, column)
      predicate = arel_column.not_eq(nil)
      return predicate unless string_like?(klass, column)

      predicate.and(arel_column.not_eq(''))
    end

    def blank_predicate(arel_column, klass, column)
      predicate = arel_column.eq(nil)
      return predicate unless string_like?(klass, column)

      predicate.or(arel_column.eq(''))
    end
  end
end