# frozen_string_literal: true

module BharatFilterEngine
  class AssociationResolver
    def initialize(scope)
      @scope = scope
    end

    def resolve(path)
      parts = path.to_s.split("__").map(&:to_sym)

      return nil if parts.empty?

      current_klass = @scope.klass
      reflections = []

      parts.each do |association_name|
        reflection =
          current_klass.reflect_on_association(
            association_name
          )

        return nil unless reflection

        reflections << reflection
        current_klass = reflection.klass
      end

      {
        associations: parts,
        reflections: reflections,
        klass: current_klass,
        table_name: current_klass.table_name
      }
    end

    def resolve_column(field)
      field = field.to_s

      # ----------------------------------------
      # Direct column
      # ----------------------------------------

      if @scope.klass.column_names.include?(field)
        return {
          column: field,
          associations: [],
          klass: @scope.klass,
          table_name: @scope.klass.table_name
        }
      end

      # ----------------------------------------
      # Nested column
      #
      # lead__client__name
      #
      # lead -> client -> name
      # ----------------------------------------

      parts = field.split("__")

      column =
        parts.pop

      association_path =
        parts.join("__")

      result =
        resolve(association_path)

      return nil unless result

      return nil unless
        result[:klass].column_names.include?(column)

      result.merge(
        column: column
      )
    end

    def join(scope, associations)
      return scope if associations.blank?

      scope.joins(
        build_nested_join(associations)
      )
    end

    private

    def build_nested_join(associations)
      associations
        .reverse
        .reduce do |nested, association|
          {
            association => nested
          }
        end
    end
  end
end