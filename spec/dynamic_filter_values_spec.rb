# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BharatFilterEngine::DynamicFilterValues do
  let!(:client_one) do
    Client.create!(
      name: 'John'
    )
  end

  let!(:client_two) do
    Client.create!(
      name: 'Jane'
    )
  end

  let!(:lead_one) do
    Lead.create!(
      source: 'google',
      client: client_one
    )
  end

  let!(:lead_two) do
    Lead.create!(
      source: 'referral',
      client: client_two
    )
  end

  before do
    Sale.create!(
      stage: 'qualified',
      lead: lead_one
    )

    Sale.create!(
      stage: 'new',
      lead: lead_two
    )
  end

  it 'returns direct values' do
    result =
      described_class.new(
        scope: Sale.all,
        field: 'stage'
      ).call

    expect(result).to eq(
      %w[new qualified]
    )
  end

  it 'returns nested values' do
    result =
      described_class.new(
        scope: Sale.all,
        field: 'lead__source'
      ).call

    expect(result).to eq(
      %w[google referral]
    )
  end

  it 'returns multi-level nested values' do
    result =
      described_class.new(
        scope: Sale.all,
        field: 'lead__client__name'
      ).call

    expect(result).to eq(
      %w[Jane John]
    )
  end

  it 'returns nil for invalid field' do
    result =
      described_class.new(
        scope: Sale.all,
        field: 'invalid_field'
      ).call

    expect(result).to be_nil
  end

  it 'returns nil for a valid association with an invalid column' do
    result =
      described_class.new(
        scope: Sale.all,
        field: 'lead__something_wrong'
      ).call

    expect(result).to be_nil
  end

  it 'returns nil for an invalid association' do
    result =
      described_class.new(
        scope: Sale.all,
        field: 'something__name'
      ).call

    expect(result).to be_nil
  end

  it 'returns nil for an invalid association at a deeper level' do
    result =
      described_class.new(
        scope: Sale.all,
        field: 'lead__something__name'
      ).call

    expect(result).to be_nil
  end

  it 'does not return blank values' do
    Sale.create!(stage: '')
    Sale.create!(stage: nil)

    result =
      described_class.new(
        scope: Sale.all,
        field: 'stage'
      ).call

    expect(result).to eq(
      %w[new qualified]
    )
  end

  it 'filters values by a partial term' do
    Sale.create!(stage: 'closed')

    result =
      described_class.new(
        scope: Sale.all,
        field: 'stage',
        term: 'qual'
      ).call

    expect(result).to eq(['qualified'])
  end

  it 'is case-insensitive when filtering by term' do
    result =
      described_class.new(
        scope: Sale.all,
        field: 'stage',
        term: 'QUAL'
      ).call

    expect(result).to eq(['qualified'])
  end

  it 'escapes LIKE wildcards in the term' do
    Sale.create!(stage: 'sale_2026')
    Sale.create!(stage: 'saleX2026')

    result =
      described_class.new(
        scope: Sale.all,
        field: 'stage',
        term: 'sale_2026'
      ).call

    expect(result).to eq(['sale_2026'])
  end

  it 'limits the number of returned values' do
    Sale.create!(stage: 'closed')

    result =
      described_class.new(
        scope: Sale.all,
        field: 'stage',
        limit: 2
      ).call

    expect(result).to eq(%w[closed new])
  end

  it 'ignores a limit of zero' do
    result =
      described_class.new(
        scope: Sale.all,
        field: 'stage',
        limit: 0
      ).call

    expect(result).to eq(%w[new qualified])
  end

  it 'combines term and limit together' do
    Sale.create!(stage: 'quarantined')
    Sale.create!(stage: 'qualified_lead')

    result =
      described_class.new(
        scope: Sale.all,
        field: 'stage',
        term: 'qua',
        limit: 1
      ).call

    expect(result).to eq(['qualified'])
  end

  it 'works with a nested field and a term together' do
    result =
      described_class.new(
        scope: Sale.all,
        field: 'lead__client__name',
        term: 'Jo'
      ).call

    expect(result).to eq(['John'])
  end
end
