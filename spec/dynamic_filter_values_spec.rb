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

  it 'returns distinct values for an integer column' do
    Sale.create!(project_id: 3)
    Sale.create!(project_id: 1)
    Sale.create!(project_id: 3)
    Sale.create!(project_id: nil)

    result = described_class.new(scope: Sale.all, field: 'project_id').call
    expect(result).to eq([1, 3])
  end

  it 'keeps a zero value for a numeric column' do
    Sale.create!(amount: 0)
    Sale.create!(amount: 5)

    result = described_class.new(scope: Sale.all, field: 'amount').call
    expect(result).to eq([0, 5])
  end

  it 'returns distinct values for a datetime column' do
    Sale.create!(actual_sale_date: Time.utc(2013, 1, 1))
    Sale.create!(actual_sale_date: nil)

    result = described_class.new(scope: Sale.all, field: 'actual_sale_date').call
    expect(result.size).to eq(1)
  end

  it 'returns distinct values for a nested integer column' do
    client = Client.create!(name: 'Nested Co')
    lead = Lead.create!(source: 'web', client: client)
    Sale.create!(lead: lead)
    Sale.create!(lead: lead)
    Sale.create!(lead: nil)

    result = described_class.new(scope: Sale.all, field: 'lead__client_id').call
    expected = Sale.joins(:lead).distinct.pluck('leads.client_id').compact.sort

    expect(result).to include(client.id)
    expect(result).to eq(expected)
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

  it 'caps invalid and oversized limits' do
    (described_class::MAX_LIMIT + 1).times do |index|
      Sale.create!(stage: "stage-#{index}")
    end

    [0, -1, 'not-a-number', 999_999_999].each do |limit|
      result = described_class.new(scope: Sale.all,field: 'stage',limit: limit).call

      expect(result.size).to eq(described_class::MAX_LIMIT)
    end
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
