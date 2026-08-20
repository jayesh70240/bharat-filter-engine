require "spec_helper"

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
      name: "John Doe",
      email: "john@example.com"
    )
  end

  let(:lead) do
    Lead.create!(
      source: "google",
      client: client,
      created_at: Time.utc(2026, 7, 20)
    )
  end

  let(:sale) do
    Sale.create!(
      stage: "qualified",
      approval_status: "approved",
      project_id: 10,
      active: true,
      amount: 500,
      actual_sale_date: Time.utc(2026, 7, 25),
      lead: lead
    )
  end

  describe ".apply" do

    it "applies string filter" do

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
            stage: "qualified"
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it "applies array filter" do

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
            status: [
              "approved",
              "pending"
            ]
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it "applies boolean filter" do

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
            active: "true"
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it "applies integer gte filter" do

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

    it "applies date range" do

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
              from: "2026-07-15",
              to: "2026-07-30"
            }
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it "applies nested filter" do

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
            lead_source: ["google"]
          }
        )

      expect(result).to contain_exactly(sale)
    end

    it "returns no records when string value does not match" do
        sale = Sale.create!(
            stage: "qualified"
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
            stage: "closed"
            }
        )

        expect(result).to be_empty
    end

    it "ignores blank string values" do
        sale = Sale.create!(
            stage: "qualified"
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
            stage: ""
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "supports multiple array values" do
        sale_one = Sale.create!(
            approval_status: "approved"
        )

        sale_two = Sale.create!(
            approval_status: "pending"
        )

        Sale.create!(
            approval_status: "rejected"
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
            status: ["approved", "pending"]
            }
        )

        expect(result).to contain_exactly(
            sale_one,
            sale_two
        )
    end

    it "normalizes comma separated values into an array" do
        sale_one = Sale.create!(
            approval_status: "approved"
        )

        sale_two = Sale.create!(
            approval_status: "pending"
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
            status: "approved,pending"
            }
        )

        expect(result).to contain_exactly(
            sale_one,
            sale_two
        )
    end

    it "filters boolean true values" do
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
            active: "true"
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "filters boolean false values" do
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

    it "filters exact integer values" do
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
            amount: "500"
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "supports integer greater than or equal filter" do
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

    it "supports integer less than or equal filter" do
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

    it "supports float filters" do
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
            conversion_rate: "12.5"
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "supports float filters" do
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
            conversion_rate: "12.5"
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "supports float greater than or equal filter" do
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

    it "filters between two dates" do
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
                from: "2026-07-01",
                to: "2026-07-31"
            }
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "supports date range with only from date" do
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
                from: "2026-08-01"
            }
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "supports date range with only to date" do
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
                to: "2026-07-31"
            }
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "supports date range array format" do
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
            actual_sale_date: [
                "2026-07-01",
                "2026-07-31"
            ]
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "supports nested string filter" do
        client = Client.create!(
            name: "John"
        )

        lead = Lead.create!(
            source: "google",
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
            lead_source: "google"
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "supports nested array filter" do
        client = Client.create!(
            name: "John"
        )

        lead_one = Lead.create!(
            source: "google",
            client: client
        )

        lead_two = Lead.create!(
            source: "referral",
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
            lead_source: ["google", "referral"]
            }
        )

        expect(result).to contain_exactly(
            sale_one,
            sale_two
        )
    end

    it "applies multiple filters together" do
        sale_one = Sale.create!(
            stage: "qualified",
            approval_status: "approved",
            amount: 500
        )

        Sale.create!(
            stage: "qualified",
            approval_status: "pending",
            amount: 500
        )

        Sale.create!(
            stage: "new",
            approval_status: "approved",
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
            stage: "qualified",
            status: ["approved"]
            }
        )

        expect(result).to contain_exactly(sale_one)
    end

    it "preserves existing scope conditions" do
        sale_one = Sale.create!(
            stage: "qualified",
            active: true
        )

        Sale.create!(
            stage: "qualified",
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
            stage: "qualified"
            }
        )

        expect(result).to contain_exactly(
            sale_one
        )
    end

    it "returns the original scope when no filters are provided" do
        sale = Sale.create!(
            stage: "qualified"
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

    it "ignores unknown params that are not present in config" do
        sale = Sale.create!(
            stage: "qualified"
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
            unknown_field: "something"
            }
        )

        expect(result).to contain_exactly(sale)
    end

    it "parses JSON array values" do
        sale_one = Sale.create!(
            approval_status: "approved"
        )

        sale_two = Sale.create!(
            approval_status: "pending"
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
  end
end