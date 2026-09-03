# frozen_string_literal: true

require_relative "lib/bharat_filter_engine/version"

Gem::Specification.new do |spec|
  spec.name = "bharat_filter_engine"
  spec.version = BharatFilterEngine::VERSION

  spec.authors = ["Jayesh Rathore"]
  spec.email = ["jayeshrathore7024@gmail.com"]

  spec.summary =
    "A generic filtering engine for Rails ActiveRecord"

  spec.description =
    "Configurable Rails ActiveRecord filtering engine supporting " \
    "string, array, boolean, numeric, date-range, nested association " \
    "and AND/OR search filters."

  spec.homepage =
    "https://github.com/jayesh70240/bharat-filter-engine"

  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir[
    "lib/**/*",
    "spec/**/*",
    "README.md",
    "LICENSE",
    "Rakefile",
    "Gemfile",
    "CHANGELOG.md"
  ]

  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 6.1"
  spec.add_dependency "activemodel", ">= 6.1"
  spec.add_dependency "activesupport", ">= 6.1"

  spec.metadata = {
    "source_code_uri" =>
      "https://github.com/jayesh70240/bharat_filter_engine",

    "changelog_uri" =>
      "https://github.com/jayesh70240/bharat_filter_engine/blob/main/CHANGELOG.md"
  }
end
