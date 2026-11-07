# frozen_string_literal: true

require 'set'

module BharatFilterEngine
  class JoinTracker
    def initialize(base_klass)
      @tables = Set.new([base_klass.table_name])
      @chains = Set.new
      @subquery_supported = base_klass.primary_key.is_a?(String)
    end

    # Returns :join or :subquery.
    def claim(result)
      chain = result[:associations]

      return :join if chain.blank?
      return :join if @chains.include?(chain)
      return :join unless @subquery_supported
      return :subquery if @tables.include?(result[:table_name])

      register(result)
      :join
    end

    private

    def register(result)
      chain = result[:associations]

      chain.each_index do |index|
        @chains << chain[0..index]
        @tables << result[:reflections][index].klass.table_name
      end
    end
  end
end