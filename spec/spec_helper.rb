# frozen_string_literal: true

require "bundler/setup"
require "active_record"
require "database_cleaner/active_record"
require "bharat_filter_engine"
require "sqlite3"

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

ActiveRecord::Schema.define do
  create_table :organizations do |t|
    t.string :name
  end

  create_table :clients do |t|
    t.string :name
    t.string :email
    t.references :organization
  end

  create_table :leads do |t|
    t.string :source
    t.string :status
    t.references :client
    t.datetime :created_at
  end

  create_table :sales do |t|
    t.string :stage
    t.string :approval_status
    t.integer :project_id
    t.boolean :active
    t.integer :amount
    t.float :conversion_rate
    t.datetime :actual_sale_date
    t.references :lead
  end
end


class Organization < ActiveRecord::Base
  has_many :clients
end


class Client < ActiveRecord::Base
  belongs_to :organization
  has_many :leads
end


class Lead < ActiveRecord::Base
  belongs_to :client
  has_many :sales
end


class Sale < ActiveRecord::Base
  belongs_to :lead
end


RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.strategy = :truncation

    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
