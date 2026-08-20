# frozen_string_literal: true

require "spec_helper"

RSpec.describe BharatFilterEngine::AssociationResolver do

  let(:resolver) do
    described_class.new(
      Sale.all
    )
  end

  describe "#resolve" do

    it "resolves a direct association" do
      result = resolver.resolve("lead")

      expect(result[:associations]).to eq(
        [:lead]
      )

      expect(result[:klass]).to eq(
        Lead
      )
    end

    it "resolves nested associations" do
      result = resolver.resolve(
        "lead__client"
      )

      expect(result[:associations]).to eq(
        [:lead, :client]
      )

      expect(result[:klass]).to eq(
        Client
      )
    end

    it "resolves multi-level associations" do
      result = resolver.resolve(
        "lead__client__organization"
      )

      expect(result[:associations]).to eq(
        [
          :lead,
          :client,
          :organization
        ]
      )

      expect(result[:klass]).to eq(
        Organization
      )
    end

    it "returns nil for invalid association" do
      result = resolver.resolve(
        "unknown"
      )

      expect(result).to be_nil
    end
  end

  describe "#resolve_column" do

    it "resolves direct columns" do
      result =
        resolver.resolve_column(
          "stage"
        )

      expect(result[:column]).to eq(
        "stage"
      )

      expect(result[:associations]).to eq([])
    end

    it "resolves nested columns" do
      result =
        resolver.resolve_column(
          "lead__source"
        )

      expect(result[:column]).to eq(
        "source"
      )

      expect(result[:associations]).to eq(
        [:lead]
      )
    end

    it "resolves multi-level columns" do
      result =
        resolver.resolve_column(
          "lead__client__name"
        )

      expect(result[:column]).to eq(
        "name"
      )

      expect(result[:associations]).to eq(
        [:lead, :client]
      )

      expect(result[:klass]).to eq(
        Client
      )
    end

    it "returns nil for invalid column" do
      result =
        resolver.resolve_column(
          "lead__invalid"
        )

      expect(result).to be_nil
    end
  end

  describe "#join" do

    it "joins one association" do
      scope =
        resolver.join(
          Sale.all,
          [:lead]
        )

      expect(
        scope.to_sql
      ).to include(
        "JOIN"
      )
    end

    it "joins nested associations" do
      scope =
        resolver.join(
          Sale.all,
          [
            :lead,
            :client
          ]
        )

      expect(
        scope.to_sql
      ).to include(
        "JOIN"
      )
    end
  end
end