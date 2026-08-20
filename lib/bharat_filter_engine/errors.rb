# frozen_string_literal: true

module BharatFilterEngine
  class Error < StandardError
  end

  class InvalidConfigurationError < Error
  end

  class InvalidFilterError < Error
  end

  class InvalidAssociationError < Error
  end
end