# frozen_string_literal: true

module BharatFilterEngine
  class SearchBuilder
    def initialize(scope:, allowed_columns:)
      @scope = scope
      @allowed_columns =
        Array(allowed_columns).map(&:to_s)
    end

    def apply(value)
      return @scope if value.blank?

      search = value.to_s.strip

      if search.include?("=")
        field_based_search(search)
      else
        simple_search(search)
      end
    end

    private

    def simple_search(search)
      query = "%#{search}%"
      conditions = []

      @allowed_columns.each do |dbcolumn|
        next unless valid_field?(dbcolumn)

        if dbcolumn.include?("__")
          @scope, condition =
            nested_condition(
              @scope,
              dbcolumn,
              query
            )

          conditions << condition if condition
        else
          table = @scope.klass.arel_table

          conditions << table[dbcolumn].matches(query)
        end
      end

      return @scope if conditions.empty?

      @scope.where(
        conditions.reduce { |left, right| left.or(right) }
      )
    end

    # field=value pairs, "&" = AND, "|" = OR within an AND group.
    #
    # If an AND group ends up with no valid conditions (e.g. every
    # field in it is unknown/blank), that group can never be satisfied
    # -- it must NOT be silently dropped, otherwise the whole search
    # is skipped and unrelated records leak through unfiltered.
    def field_based_search(search)
      and_conditions =
        search.split("&").map do |and_group|
          or_conditions =
            and_group.split("|").filter_map do |expression|
              field, search_value =
                expression.split("=", 2)

              next if field.blank?
              next if search_value.blank?
              next unless valid_field?(field)

              query = "%#{search_value.strip}%"

              if field.include?("__")
                @scope, condition =
                  nested_condition(
                    @scope,
                    field,
                    query
                  )

                condition
              elsif field == "id"
                quoted_column =
                  @scope.klass
                        .connection
                        .quote_column_name(field)

                Arel.sql(
                  "#{@scope.klass.quoted_table_name}.#{quoted_column}::text"
                ).matches(query)
              else
                @scope.klass.arel_table[field].matches(query)
              end
            end

          # Every expression in this AND group was invalid/unmatchable,
          # so the whole search can never match anything.
          return @scope.none if or_conditions.empty?

          or_conditions.reduce { |left, right| left.or(right) }
        end

      return @scope if and_conditions.empty?

      @scope.where(
        and_conditions.reduce { |left, right| left.and(right) }
      )
    end

    def valid_field?(field)
      if field.include?("__")
        !resolver.resolve_column(field).nil?
      else
        @scope.klass.column_names.include?(field)
      end
    end

    def nested_condition(scope, field, query)
      result = resolver.resolve_column(field)

      return [scope, nil] unless result

      joined_scope =
        resolver.join(
          scope,
          result[:associations]
        )

      condition =
        result[:klass]
          .arel_table[result[:column]]
          .matches(query)

      [joined_scope, condition]
    end

    # AssociationResolver only needs @scope.klass (which never changes
    # across joins), so a single instance can be reused for the whole
    # search instead of being rebuilt every time the scope is updated.
    def resolver
      @resolver ||= AssociationResolver.new(@scope)
    end
  end
end
