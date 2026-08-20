require "spec_helper"

RSpec.describe BharatFilterEngine::RuleNormalizer do

    it "keeps modern configuration unchanged" do

        rule = {
        type: :single,
        filter_type: :string,
        dbcolumn: :stage
        }

        expect(
        described_class.call(rule)
        ).to eq(rule)
    end

    it "supports legacy configuration" do

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

    it "returns nil for nil rule" do
        expect(
            described_class.call(nil)
        ).to be_nil
    end

    it "symbolizes rule keys" do
        result = described_class.call(
            "type" => :single,
            "filter_type" => :string,
            "dbcolumn" => :stage
        )

        expect(result[:type]).to eq(:single)
        expect(result[:filter_type]).to eq(:string)
        expect(result[:dbcolumn]).to eq(:stage)
    end
end