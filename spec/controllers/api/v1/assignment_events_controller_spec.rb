require 'rails_helper'

RSpec.describe Api::V1::AssignmentEventsController do
  describe "#create" do
    let!(:visitor) { FactoryBot.create(:visitor, id: "7ab083a5-d532-4bd6-912f-aa7e887450da") }
    let(:split) { FactoryBot.create(:split, name: "my_split", registry: { control: 47, treatment: 1, zombie_apocalypse: 52 }) }

    let(:create_params) do
      {
        visitor_id: visitor.id,
        split_name: split.name,
        mixpanel_result: "success",
        context: "context"
      }
    end

    it "creates an assignment if none already exists" do
      expect {
        post :create, params: create_params
      }.to change { Assignment.count }.by(1)

      expect(response).to have_http_status :no_content

      assignment = Assignment.first
      expect(assignment.variant).to eq "treatment"
      expect(assignment.visitor).to eq visitor
      expect(assignment.split).to eq split
      expect(assignment.mixpanel_result).to eq "success"
      expect(assignment.context).to eq "context"
    end

    it "noops if a conflicting assignment with a mixpanel_result already exists" do
      assignment = nil
      Timecop.freeze(1.year.ago) do
        assignment = FactoryBot.create(:assignment, visitor:, split:, variant: "control", mixpanel_result: "success")
      end

      assignment.reload
      original_attributes = assignment.attributes

      expect {
        post :create, params: create_params
      }.not_to change { PreviousAssignment.count }

      expect(response).to have_http_status :no_content
      expect(assignment.reload.attributes).to eq original_attributes
    end

    it "updates an existing assignment without a mixpanel_result" do
      assignment = nil
      Timecop.freeze(1.year.ago) do
        assignment = FactoryBot.create(:assignment, visitor:, split:, variant: "control", mixpanel_result: nil)
      end

      assignment.reload

      expect {
        post :create, params: create_params
      }.not_to change { PreviousAssignment.count }

      expect(response).to have_http_status :no_content
      assignment = Assignment.first
      expect(assignment.mixpanel_result).to eq "success"
    end

    it "allows a request without a mixpanel_result" do
      post :create, params: create_params.except(:mixpanel_result)

      expect(response).to have_http_status :no_content

      assignment = Assignment.first
      expect(assignment.variant).to eq "treatment"
      expect(assignment.visitor).to eq visitor
      expect(assignment.split).to eq split
      expect(assignment.mixpanel_result).to be_nil
      expect(assignment.context).to eq "context"
    end
  end
end
