#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: ruby script/verify_release_tag.rb v0.2.0
#
# Fails (exit 1) unless the git tag matches BharatFilterEngine::VERSION, so a
# release can never publish a gem whose version differs from its tag.
# Compares canonical RubyGems versions, so for version '0.2.0pre' the tags
# v0.2.0pre and v0.2.0.pre both match. NOTE: RubyGems reads a hyphen as
# '.pre.', so '0.2.0-pre' is the version 0.2.0.pre.pre -- a different version,
# and is rejected on purpose rather than publishing something unexpected.
# When running in GitHub Actions it also writes `prerelease=true|false`
# and `version=<canonical version>` to $GITHUB_OUTPUT.

require 'rubygems'
require_relative '../lib/bharat_filter_engine/version'

tag = ARGV.fetch(0) { abort 'usage: verify_release_tag.rb <tag>' }
raw = tag.sub(/\Av/, '')

abort "Tag #{tag.inspect} is not a valid version" unless Gem::Version.correct?(raw)

tag_version = Gem::Version.new(raw)
gem_version = Gem::Version.new(BharatFilterEngine::VERSION)

unless tag_version == gem_version
  abort "Tag #{tag} (#{tag_version}) does not match lib/bharat_filter_engine/version.rb " \
        "(#{BharatFilterEngine::VERSION} => #{gem_version}). Bump the version or re-tag " \
        "(for a pre-release use e.g. v#{gem_version})."
end

changelog = File.expand_path('../CHANGELOG.md', __dir__)
if File.exist?(changelog)
  text = File.read(changelog)
  mentioned = [gem_version.to_s, BharatFilterEngine::VERSION, raw].any? { |v| text.include?(v) }
  puts "::warning::CHANGELOG.md does not mention #{raw}" unless mentioned
end

puts "OK: tag #{tag} matches gem version #{gem_version} (prerelease=#{gem_version.prerelease?})"

if (out = ENV['GITHUB_OUTPUT'])
  File.open(out, 'a') do |f|
    f.puts "prerelease=#{gem_version.prerelease?}"
    f.puts "version=#{gem_version}"
  end
end
