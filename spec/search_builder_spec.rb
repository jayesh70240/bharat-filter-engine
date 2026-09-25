# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BharatFilterEngine::SearchBuilder do
  let!(:client) do
    Client.create!(
      name: 'John Doe',
      email: 'john@example.com'
    )
  end

  let!(:lead) do
    Lead.create!(
      source: 'google',
      client: client
    )
  end

  let!(:sale) do
    Sale.create!(
      stage: 'qualified',
      lead: lead
    )
  end

  it 'supports simple search' do
    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: %i[
          stage
          lead__source
        ]
      ).apply('google')

    expect(result).to contain_exactly(sale)
  end

  it 'supports case insensitive search' do
    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [:stage]
      ).apply('QUAL')

    expect(result).to contain_exactly(sale)
  end

  it 'supports nested field search' do
    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [
          :lead__client__name
        ]
      ).apply(
        'lead__client__name=John'
      )

    expect(result).to contain_exactly(sale)
  end

  it 'supports multi-level association search' do
    organization = Organization.create!(
      name: 'Acme'
    )

    client_two = Client.create!(
      name: 'Jane',
      organization: organization
    )

    lead_two = Lead.create!(
      source: 'referral',
      client: client_two
    )

    sale_two = Sale.create!(
      lead: lead_two
    )

    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [
          :lead__client__organization__name
        ]
      ).apply(
        'lead__client__organization__name=Acme'
      )

    expect(result).to contain_exactly(sale_two)
  end

  it 'supports OR search' do
    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: %i[
          stage
          lead__source
        ]
      ).apply(
        'stage=qualified|lead__source=google'
      )

    expect(result).to contain_exactly(sale)
  end

  it 'supports combined AND and OR conditions' do
    sale_one = Sale.create!(
      stage: 'qualified',
      approval_status: 'approved'
    )

    sale_two = Sale.create!(
      stage: 'qualified',
      approval_status: 'pending'
    )

    Sale.create!(
      stage: 'new',
      approval_status: 'approved'
    )

    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: %i[
          stage
          approval_status
        ]
      ).apply(
        'stage=qualified&approval_status=approved|approval_status=pending'
      )

    expect(result).to contain_exactly(
      sale_one,
      sale_two
    )
  end

  it 'returns no records when the searched field is not configured' do
    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [:stage]
      ).apply(
        'unknown=value'
      )

    expect(result).to be_empty
  end

  it 'supports searching the id column as text' do
    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [:id]
      ).apply(
        "id=#{sale.id}"
      )

    expect(result).to contain_exactly(sale)
  end

  it "handles a value that itself contains an '=' sign" do
    sale_with_url = Sale.create!(
      stage: 'https://example.com?x=1'
    )

    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [:stage]
      ).apply(
        'stage=https://example.com?x=1'
      )

    expect(result).to contain_exactly(sale_with_url)
  end

  it 'skips a whitespace-only expression value' do
    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [:stage]
      ).apply(
        'stage=   '
      )

    # every expression in the (only) AND group is blank/skipped, so
    # the group can never match anything
    expect(result).to be_empty
  end

  it 'returns the scope unchanged when allowed_columns is empty' do
    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: []
      ).apply('anything')

    expect(result).to contain_exactly(sale)
  end

  it 'raises when none of the allowed_columns can be resolved' do
    expect do
      described_class.new(
        scope: Sale.all,
        allowed_columns: %i[
          totally_not_a_column
          also__not__real
        ]
      )
    end.to raise_error(BharatFilterEngine::InvalidConfigurationError)
  end

  it 'does not raise when only some allowed_columns are invalid' do
    expect do
      described_class.new(
        scope: Sale.all,
        allowed_columns: %i[
          stage
          totally_not_a_column
        ]
      )
    end.not_to raise_error
  end

  it 'reuses a single AssociationResolver across a whole search' do
    allow(BharatFilterEngine::AssociationResolver)
      .to receive(:new)
      .and_call_original

    described_class.new(
      scope: Sale.all,
      allowed_columns: %i[
        lead__source
        lead__client__name
      ]
    ).apply(
      'lead__source=google&lead__client__name=John'
    )

    expect(BharatFilterEngine::AssociationResolver)
      .to have_received(:new)
      .once
  end

  describe 'LIKE wildcard escaping' do
    it 'treats a literal underscore as a literal character, not a wildcard' do
      match = Sale.create!(stage: 'sale_2026')
      Sale.create!(stage: 'saleX2026')

      result =
        described_class.new(
          scope: Sale.all,
          allowed_columns: [:stage]
        ).apply('sale_2026')

      expect(result).to contain_exactly(match)
    end

    it 'treats a literal percent sign as a literal character, not a wildcard' do
      match = Sale.create!(stage: '50%off')
      Sale.create!(stage: '50xoff')

      result =
        described_class.new(
          scope: Sale.all,
          allowed_columns: [:stage]
        ).apply('50%off')

      expect(result).to contain_exactly(match)
    end

    it 'escapes wildcards in field-based search too' do
      match = Sale.create!(stage: 'sale_2026')
      Sale.create!(stage: 'saleX2026')

      result =
        described_class.new(
          scope: Sale.all,
          allowed_columns: [:stage]
        ).apply('stage=sale_2026')

      expect(result).to contain_exactly(match)
    end
  end
end
