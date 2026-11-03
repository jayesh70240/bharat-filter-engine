# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BharatFilterEngine::Engine do
  # `let` (not `let!`) on purpose: these fixtures are only referenced
  # by name in the first few examples below ("applies string filter",
  # etc). Every other example in this file builds its own local
  # `sale`/`sale_one`/`sale_two` records. If these were `let!` they'd
  # be created unconditionally before *every* example in the file,
  # and this record (stage: "qualified", approval_status: "approved",
  # active: true, amount: 500) would leak into unrelated examples'
  # results whenever their filter happens to match it.
  let(:client) do
    Client.create!(
      name: 'John Doe',
      email: 'john@example.com'
    )
  end

  let(:lead) do
    Lead.create!(
      source: 'google',
      client: client,
      created_at: Time.utc(2026, 7, 20)
    )
  end

  let(:sale) do
    Sale.create!(
      stage: 'qualified',
      approval_status: 'approved',
      project_id: 10,
      active: true,
      amount: 500,
      actual_sale_date: Time.utc(2026, 7, 25),
      lead: lead
    )
  end

  describe '.apply' do
    it 'applies string filter' do
      config = {
        stage: {
          type: :single,
          filter_type: :string,
          dbcolumn: :stage
        }
      }

      result =
        described_class.apply(
          scope: Sale.all,
          config: config,
          params: {
            stage: 'qualified'
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it 'applies array filter' do
      config = {
        status: {
          type: :single,
          filter_type: :array,
          dbcolumn: :approval_status
        }
      }

      result =
        described_class.apply(
          scope: Sale.all,
          config: config,
          params: {
            status: %w[
              approved
              pending
            ]
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it 'applies boolean filter' do
      config = {
        active: {
          type: :single,
          filter_type: :boolean,
          dbcolumn: :active
        }
      }

      result =
        described_class.apply(
          scope: Sale.all,
          config: config,
          params: {
            active: 'true'
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it 'applies integer gte filter' do
      config = {
        amount: {
          type: :single,
          filter_type: :integer,
          dbcolumn: :amount,
          range_type: :gte
        }
      }

      result =
        described_class.apply(
          scope: Sale.all,
          config: config,
          params: {
            amount: 400
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it 'applies date range' do
      config = {
        actual_sale_date: {
          type: :single,
          filter_type: :daterange,
          dbcolumn: :actual_sale_date
        }
      }

      result =
        described_class.apply(
          scope: Sale.all,
          config: config,
          params: {
            actual_sale_date: {
              from: '2026-07-15',
              to: '2026-07-30'
            }
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it 'applies nested filter' do
      config = {
        lead_source: {
          type: :nested,
          filter_type: :array,
          association: :lead,
          dbcolumn: :source
        }
      }

      result =
        described_class.apply(
          scope: Sale.all,
          config: config,
          params: {
            lead_source: ['google']
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it 'returns no records when string value does not match' do
      Sale.create!(
        stage: 'qualified'
      )

      config = {
        stage: {
          type: :single,
          filter_type: :string,
          dbcolumn: :stage
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          stage: 'closed'
        }
      )

      expect(result).to be_empty
    end

    it 'ignores blank string values' do
      sale = Sale.create!(
        stage: 'qualified'
      )

      config = {
        stage: {
          type: :single,
          filter_type: :string,
          dbcolumn: :stage
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          stage: ''
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'ignores a nil filter value' do
      sale = Sale.create!(
        stage: 'qualified'
      )

      config = {
        stage: {
          type: :single,
          filter_type: :string,
          dbcolumn: :stage
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          stage: nil
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'ignores an empty array filter value' do
      sale = Sale.create!(
        approval_status: 'approved'
      )

      config = {
        status: {
          type: :single,
          filter_type: :array,
          dbcolumn: :approval_status
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          status: []
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'returns the original scope unchanged for an empty config' do
      sale = Sale.create!(
        stage: 'qualified'
      )

      result = described_class.apply(
        scope: Sale.all,
        config: {},
        params: {
          stage: 'qualified'
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'supports multiple array values' do
      sale_one = Sale.create!(
        approval_status: 'approved'
      )

      sale_two = Sale.create!(
        approval_status: 'pending'
      )

      Sale.create!(
        approval_status: 'rejected'
      )

      config = {
        status: {
          type: :single,
          filter_type: :array,
          dbcolumn: :approval_status
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          status: %w[approved pending]
        }
      )

      expect(result).to contain_exactly(
        sale_one,
        sale_two
      )
    end

    it 'normalizes comma separated values into an array' do
      sale_one = Sale.create!(
        approval_status: 'approved'
      )

      sale_two = Sale.create!(
        approval_status: 'pending'
      )

      config = {
        status: {
          type: :single,
          filter_type: :array,
          dbcolumn: :approval_status
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          status: 'approved,pending'
        }
      )

      expect(result).to contain_exactly(
        sale_one,
        sale_two
      )
    end

    it 'filters boolean true values' do
      sale = Sale.create!(
        active: true
      )

      Sale.create!(
        active: false
      )

      config = {
        active: {
          type: :single,
          filter_type: :boolean,
          dbcolumn: :active
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          active: 'true'
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'filters boolean false values' do
      Sale.create!(
        active: true
      )

      sale = Sale.create!(
        active: false
      )

      config = {
        active: {
          type: :single,
          filter_type: :boolean,
          dbcolumn: :active
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          active: false
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'filters exact integer values' do
      sale = Sale.create!(
        amount: 500
      )

      Sale.create!(
        amount: 1000
      )

      config = {
        amount: {
          type: :single,
          filter_type: :integer,
          dbcolumn: :amount
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          amount: '500'
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'filters an exact integer value of zero' do
      sale = Sale.create!(
        amount: 0
      )

      Sale.create!(
        amount: 500
      )

      config = {
        amount: {
          type: :single,
          filter_type: :integer,
          dbcolumn: :amount
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          amount: 0
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'supports integer greater than or equal filter' do
      sale_one = Sale.create!(
        amount: 500
      )

      sale_two = Sale.create!(
        amount: 1000
      )

      Sale.create!(
        amount: 200
      )

      config = {
        amount: {
          type: :single,
          filter_type: :integer,
          dbcolumn: :amount,
          range_type: :gte
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          amount: 500
        }
      )

      expect(result).to contain_exactly(
        sale_one,
        sale_two
      )
    end

    it 'supports integer less than or equal filter' do
      sale_one = Sale.create!(
        amount: 500
      )

      sale_two = Sale.create!(
        amount: 200
      )

      Sale.create!(
        amount: 1000
      )

      config = {
        amount: {
          type: :single,
          filter_type: :integer,
          dbcolumn: :amount,
          range_type: :lte
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          amount: 500
        }
      )

      expect(result).to contain_exactly(
        sale_one,
        sale_two
      )
    end

    it 'supports integer between filter with a hash' do
      sale_one = Sale.create!(amount: 500)
      sale_two = Sale.create!(amount: 800)

      Sale.create!(amount: 100)
      Sale.create!(amount: 1500)

      config = {
        amount: {
          type: :single,
          filter_type: :integer,
          dbcolumn: :amount,
          range_type: :between
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          amount: { from: 300, to: 1000 }
        }
      )

      expect(result).to contain_exactly(
        sale_one,
        sale_two
      )
    end

    it 'supports integer between filter with an array' do
      sale_one = Sale.create!(amount: 500)
      sale_two = Sale.create!(amount: 800)

      Sale.create!(amount: 100)

      config = {
        amount: {
          type: :single,
          filter_type: :integer,
          dbcolumn: :amount,
          range_type: :between
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          amount: [300, 1000]
        }
      )

      expect(result).to contain_exactly(
        sale_one,
        sale_two
      )
    end

    it 'supports integer between filter with only a lower bound' do
      sale_one = Sale.create!(amount: 500)
      sale_two = Sale.create!(amount: 800)

      Sale.create!(amount: 100)

      config = {
        amount: {
          type: :single,
          filter_type: :integer,
          dbcolumn: :amount,
          range_type: :between
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          amount: { from: 300 }
        }
      )

      expect(result).to contain_exactly(
        sale_one,
        sale_two
      )
    end

    it 'supports float between filter' do
      sale = Sale.create!(conversion_rate: 12.5)

      Sale.create!(conversion_rate: 1.0)
      Sale.create!(conversion_rate: 99.0)

      config = {
        conversion_rate: {
          type: :single,
          filter_type: :float,
          dbcolumn: :conversion_rate,
          range_type: :between
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          conversion_rate: { from: 10.0, to: 15.0 }
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'supports float filters' do
      sale = Sale.create!(
        conversion_rate: 12.5
      )

      Sale.create!(
        conversion_rate: 20.5
      )

      config = {
        conversion_rate: {
          type: :single,
          filter_type: :float,
          dbcolumn: :conversion_rate
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          conversion_rate: '12.5'
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'supports float greater than or equal filter' do
      sale_one = Sale.create!(
        conversion_rate: 10.5
      )

      sale_two = Sale.create!(
        conversion_rate: 20.5
      )

      Sale.create!(
        conversion_rate: 5.5
      )

      config = {
        conversion_rate: {
          type: :single,
          filter_type: :float,
          dbcolumn: :conversion_rate,
          range_type: :gte
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          conversion_rate: 10.5
        }
      )

      expect(result).to contain_exactly(
        sale_one,
        sale_two
      )
    end

    it 'filters between two dates' do
      sale = Sale.create!(
        actual_sale_date: Time.utc(2026, 7, 20)
      )

      Sale.create!(
        actual_sale_date: Time.utc(2026, 8, 20)
      )

      config = {
        actual_sale_date: {
          type: :single,
          filter_type: :daterange,
          dbcolumn: :actual_sale_date
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          actual_sale_date: {
            from: '2026-07-01',
            to: '2026-07-31'
          }
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'supports date range with only from date' do
      sale = Sale.create!(
        actual_sale_date: Time.utc(2026, 8, 10)
      )

      Sale.create!(
        actual_sale_date: Time.utc(2026, 7, 10)
      )

      config = {
        actual_sale_date: {
          type: :single,
          filter_type: :daterange,
          dbcolumn: :actual_sale_date
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          actual_sale_date: {
            from: '2026-08-01'
          }
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'supports date range with only to date' do
      sale = Sale.create!(
        actual_sale_date: Time.utc(2026, 7, 10)
      )

      Sale.create!(
        actual_sale_date: Time.utc(2026, 8, 10)
      )

      config = {
        actual_sale_date: {
          type: :single,
          filter_type: :daterange,
          dbcolumn: :actual_sale_date
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          actual_sale_date: {
            to: '2026-07-31'
          }
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'supports date range array format' do
      sale = Sale.create!(
        actual_sale_date: Time.utc(2026, 7, 20)
      )

      config = {
        actual_sale_date: {
          type: :single,
          filter_type: :daterange,
          dbcolumn: :actual_sale_date
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          actual_sale_date: %w[
            2026-07-01
            2026-07-31
          ]
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'supports nested string filter' do
      client = Client.create!(
        name: 'John'
      )

      lead = Lead.create!(
        source: 'google',
        client: client
      )

      sale = Sale.create!(
        lead: lead
      )

      config = {
        lead_source: {
          type: :nested,
          filter_type: :string,
          association: :lead,
          dbcolumn: :source
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          lead_source: 'google'
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'supports nested array filter' do
      client = Client.create!(
        name: 'John'
      )

      lead_one = Lead.create!(
        source: 'google',
        client: client
      )

      lead_two = Lead.create!(
        source: 'referral',
        client: client
      )

      sale_one = Sale.create!(lead: lead_one)
      sale_two = Sale.create!(lead: lead_two)

      config = {
        lead_source: {
          type: :nested,
          filter_type: :array,
          association: :lead,
          dbcolumn: :source
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          lead_source: %w[google referral]
        }
      )

      expect(result).to contain_exactly(
        sale_one,
        sale_two
      )
    end

    it "raises InvalidAssociationError when a nested rule's association cannot be resolved" do
      config = {
        lead_source: {
          type: :nested,
          filter_type: :string,
          association: :not_a_real_association,
          dbcolumn: :source
        }
      }

      expect do
        described_class.apply(
          scope: Sale.all,
          config: config,
          params: { lead_source: 'google' }
        )
      end.to raise_error(BharatFilterEngine::InvalidAssociationError)
    end

    it 'applies multiple filters together' do
      sale_one = Sale.create!(
        stage: 'qualified',
        approval_status: 'approved',
        amount: 500
      )

      Sale.create!(
        stage: 'qualified',
        approval_status: 'pending',
        amount: 500
      )

      Sale.create!(
        stage: 'new',
        approval_status: 'approved',
        amount: 500
      )

      config = {
        stage: {
          type: :single,
          filter_type: :string,
          dbcolumn: :stage
        },

        status: {
          type: :single,
          filter_type: :array,
          dbcolumn: :approval_status
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          stage: 'qualified',
          status: ['approved']
        }
      )

      expect(result).to contain_exactly(sale_one)
    end

    it 'preserves existing scope conditions' do
      sale_one = Sale.create!(
        stage: 'qualified',
        active: true
      )

      Sale.create!(
        stage: 'qualified',
        active: false
      )

      base_scope =
        Sale.where(active: true)

      config = {
        stage: {
          type: :single,
          filter_type: :string,
          dbcolumn: :stage
        }
      }

      result = described_class.apply(
        scope: base_scope,
        config: config,
        params: {
          stage: 'qualified'
        }
      )

      expect(result).to contain_exactly(
        sale_one
      )
    end

    it 'returns the original scope when no filters are provided' do
      sale = Sale.create!(
        stage: 'qualified'
      )

      config = {
        stage: {
          type: :single,
          filter_type: :string,
          dbcolumn: :stage
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {}
      )

      expect(result).to contain_exactly(sale)
    end

    it 'ignores unknown params that are not present in config' do
      sale = Sale.create!(
        stage: 'qualified'
      )

      config = {
        stage: {
          type: :single,
          filter_type: :string,
          dbcolumn: :stage
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          unknown_field: 'something'
        }
      )

      expect(result).to contain_exactly(sale)
    end

    it 'parses JSON array values' do
      sale_one = Sale.create!(
        approval_status: 'approved'
      )

      sale_two = Sale.create!(
        approval_status: 'pending'
      )

      config = {
        status: {
          type: :single,
          filter_type: :array,
          dbcolumn: :approval_status
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: {
          status: '["approved","pending"]'
        }
      )

      expect(result).to contain_exactly(
        sale_one,
        sale_two
      )
    end

    it 'supports a config-driven search filter' do
      client = Client.create!(name: 'John')
      lead = Lead.create!(source: 'google', client: client)
      sale = Sale.create!(stage: 'qualified', lead: lead)

      Sale.create!(stage: 'new')

      config = {
        q: {
          type: :single,
          filter_type: :search,
          dbcolumns: %i[stage lead__source]
        }
      }

      result = described_class.apply(
        scope: Sale.all,
        config: config,
        params: { q: 'google' }
      )

      expect(result).to contain_exactly(sale)
    end

    describe 'negate' do
      it 'excludes matching string values' do
        sale = Sale.create!(stage: 'new')
        Sale.create!(stage: 'qualified')

        config = {
          stage: {
            type: :single,
            filter_type: :string,
            dbcolumn: :stage,
            negate: true
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { stage: 'qualified' }
        )

        expect(result).to contain_exactly(sale)
      end

      it 'excludes matching array values' do
        sale = Sale.create!(approval_status: 'rejected')
        Sale.create!(approval_status: 'approved')
        Sale.create!(approval_status: 'pending')

        config = {
          status: {
            type: :single,
            filter_type: :array,
            dbcolumn: :approval_status,
            negate: true
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { status: %w[approved pending] }
        )

        expect(result).to contain_exactly(sale)
      end

      it 'excludes matching boolean values' do
        sale = Sale.create!(active: false)
        Sale.create!(active: true)

        config = {
          active: {
            type: :single,
            filter_type: :boolean,
            dbcolumn: :active,
            negate: true
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { active: 'true' }
        )

        expect(result).to contain_exactly(sale)
      end

      it 'excludes an exact integer match' do
        sale = Sale.create!(amount: 1000)
        Sale.create!(amount: 500)

        config = {
          amount: {
            type: :single,
            filter_type: :integer,
            dbcolumn: :amount,
            negate: true
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { amount: 500 }
        )

        expect(result).to contain_exactly(sale)
      end

      it 'works on a nested (associated) column' do
        client = Client.create!(name: 'John')
        lead_google = Lead.create!(source: 'google', client: client)
        lead_referral = Lead.create!(source: 'referral', client: client)

        sale = Sale.create!(lead: lead_referral)
        Sale.create!(lead: lead_google)

        config = {
          lead_source: {
            type: :nested,
            filter_type: :string,
            association: :lead,
            dbcolumn: :source,
            negate: true
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { lead_source: 'google' }
        )

        expect(result).to contain_exactly(sale)
      end

      it 'excludes matching array values on a nested (associated) column' do
        client = Client.create!(name: 'John')
        lead_google = Lead.create!(source: 'google', client: client)
        lead_referral = Lead.create!(source: 'referral', client: client)
        lead_direct = Lead.create!(source: 'direct', client: client)

        sale = Sale.create!(lead: lead_direct)
        Sale.create!(lead: lead_google)
        Sale.create!(lead: lead_referral)

        config = {
          lead_source: {
            type: :nested,
            filter_type: :array,
            association: :lead,
            dbcolumn: :source,
            negate: true
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { lead_source: %w[google referral] }
        )

        expect(result).to contain_exactly(sale)
      end

      it 'excludes an array value that itself contains nil' do
        sale = Sale.create!(approval_status: 'rejected')
        Sale.create!(approval_status: 'approved')
        Sale.create!(approval_status: nil)

        config = {
          status: {
            type: :single,
            filter_type: :array,
            dbcolumn: :approval_status,
            negate: true
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { status: [nil, 'approved'] }
        )

        expect(result).to contain_exactly(sale)
      end
    end

    describe 'presence filter' do
      it 'returns records where the column is present when value is true' do
        sale = Sale.create!(stage: 'qualified')
        Sale.create!(stage: nil)
        Sale.create!(stage: '')

        config = {
          has_stage: {
            type: :single,
            filter_type: :presence,
            dbcolumn: :stage
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { has_stage: 'true' }
        )

        expect(result).to contain_exactly(sale)
      end

      it 'returns records where the column is blank when value is false' do
        Sale.create!(stage: 'qualified')
        sale_nil = Sale.create!(stage: nil)
        sale_blank = Sale.create!(stage: '')

        config = {
          has_stage: {
            type: :single,
            filter_type: :presence,
            dbcolumn: :stage
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { has_stage: 'false' }
        )

        expect(result).to contain_exactly(
          sale_nil,
          sale_blank
        )
      end

      it 'works on a nested (associated) column' do
        client_with_org = Client.create!(
          name: 'John',
          organization: Organization.create!(name: 'Acme')
        )

        client_without_org = Client.create!(name: 'Jane')

        lead_one = Lead.create!(source: 'google', client: client_with_org)
        lead_two = Lead.create!(source: 'referral', client: client_without_org)

        sale_with_org = Sale.create!(lead: lead_one)
        Sale.create!(lead: lead_two)

        config = {
          has_organization: {
            type: :nested,
            filter_type: :presence,
            association: :lead__client,
            dbcolumn: :organization_id
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { has_organization: 'true' }
        )

        expect(result).to contain_exactly(sale_with_org)
      end
    end
    describe 'invalid numeric input' do
      it 'ignores a non-numeric exact integer filter value' do
        sale = Sale.create!(amount: 500)

        config = {
          amount: {
            type: :single,
            filter_type: :integer,
            dbcolumn: :amount
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { amount: 'abc' }
        )

        expect(result).to contain_exactly(sale)
      end

      it 'ignores a non-numeric gte filter value' do
        sale = Sale.create!(amount: 500)

        config = {
          amount: {
            type: :single,
            filter_type: :integer,
            dbcolumn: :amount,
            range_type: :gte
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { amount: 'not-a-number' }
        )

        expect(result).to contain_exactly(sale)
      end

      it 'honors the valid bound and ignores an invalid bound in a between filter' do
        sale_one = Sale.create!(amount: 100)
        sale_two = Sale.create!(amount: 900)
        Sale.create!(amount: 2000)

        config = {
          amount: {
            type: :single,
            filter_type: :integer,
            dbcolumn: :amount,
            range_type: :between
          }
        }

        result = described_class.apply(
          scope: Sale.all,
          config: config,
          params: { amount: { from: 'not-a-number', to: 1000 } }
        )

        expect(result).to contain_exactly(
          sale_one,
          sale_two
        )
      end
    end
  end
end
