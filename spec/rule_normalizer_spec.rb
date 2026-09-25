# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BharatFilterEngine::RuleNormalizer do
  it 'keeps modern configuration unchanged' do
    rule = {
      type: :single,
      filter_type: :string,
      dbcolumn: :stage
    }

    expect(
      described_class.call(rule)
    ).to eq(rule)
  end

  it 'supports legacy configuration' do
    result =
      described_class.call(
        type: :string,
        dbcolumn: :stage
      )

    expect(
      result[:type]
    ).to eq(:single)

    expect(
      result[:filter_type]
    ).to eq(:string)
  end

  it 'returns nil for nil rule' do
    expect(
      described_class.call(nil)
    ).to be_nil
  end

  it 'symbolizes rule keys' do
    result = described_class.call(
      'type' => :single,
      'filter_type' => :string,
      'dbcolumn' => :stage
    )

        expect(result[:type]).to eq(:single)
        expect(result[:filter_type]).to eq(:string)
        expect(result[:dbcolumn]).to eq(:stage)
    end

    describe "validation" do
        it "raises for an unknown filter_type" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :not_a_real_type,
                    dbcolumn: :stage
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "raises when a nested rule is missing association" do
            expect {
                described_class.call(
                    type: :nested,
                    filter_type: :string,
                    dbcolumn: :source
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "raises when a search rule is missing dbcolumns" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :search
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "raises when a search rule has an empty dbcolumns array" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :search,
                    dbcolumns: []
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "raises when a non-search rule is missing dbcolumn" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :string
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "raises for an unknown range_type" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :integer,
                    dbcolumn: :amount,
                    range_type: :nonsense
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "raises when range_type is used on a non-numeric filter_type" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :string,
                    dbcolumn: :stage,
                    range_type: :gte
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "allows range_type: :between on integer/float filters" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :integer,
                    dbcolumn: :amount,
                    range_type: :between
                )
            }.not_to raise_error
        end

        it "raises when negate is combined with range_type" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :integer,
                    dbcolumn: :amount,
                    range_type: :gte,
                    negate: true
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "raises when negate is combined with a daterange filter" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :daterange,
                    dbcolumn: :actual_sale_date,
                    negate: true
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "raises when negate is combined with a search filter" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :search,
                    dbcolumns: [:stage],
                    negate: true
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "raises when negate is combined with a presence filter" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :presence,
                    dbcolumn: :stage,
                    negate: true
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end

        it "allows negate on a plain string/array/boolean/exact-numeric filter" do
            expect {
                described_class.call(
                    type: :single,
                    filter_type: :string,
                    dbcolumn: :stage,
                    negate: true
                )
            }.not_to raise_error
        end

        it "raises when filter_type: :search is combined with type: :nested" do
            expect {
                described_class.call(
                    type: :nested,
                    filter_type: :search,
                    association: :lead,
                    dbcolumns: [:source]
                )
            }.to raise_error(BharatFilterEngine::InvalidConfigurationError)
        end
    end
end
