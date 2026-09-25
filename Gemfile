# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'activemodel', '>= 6.1'
gem 'activerecord', '>= 6.1'
gem 'activesupport', '>= 6.1'

group :development, :test do
  gem 'rake'
  gem 'rspec'
  gem 'rubocop-rails-omakase', require: false
  gem 'sqlite3'
end

group :test do
  gem 'database_cleaner-active_record'
end
