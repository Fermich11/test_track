require 'rails_helper'

RSpec.describe Assignment do
  let(:split) { FactoryBot.create(:split) }
  subject { FactoryBot.create(:assignment, split:) }

  describe "variant" do
    it "validates presence of variant" do
      expect(subject).to validate_presence_of(:variant)
    end

    it "ensures validity of variant" do
      subject.variant = :not_really_a_variant
      expect(subject).not_to be_valid
      expect(subject.errors).to be_added(:variant, "must be specified in split's current variants")
    end
  end

  describe "split" do
    it "validates presence of split_id" do
      expect(subject).to validate_presence_of(:split).with_message(:required)
    end
  end

  describe "visitor" do
    it "validates presence of visitor_id" do
      expect(subject).to validate_presence_of(:visitor).with_message(:required)
    end
  end

  describe "mixpanel_result" do
    it "allows 'succcess'" do
      subject.mixpanel_result = "success"
      expect(subject).to be_valid
    end

    it "allows 'failure'" do
      subject.mixpanel_result = "failure"
      expect(subject).to be_valid
    end

    it "allows nil" do
      subject.mixpanel_result = nil
      expect(subject).to be_valid
    end

    it "allows empty string" do
      subject.mixpanel_result = ""
      expect(subject).to be_valid
    end

    it "normalizes" do
      expect(subject).to normalize_attribute(:mixpanel_result)
    end

    it "does not allow other values" do
      subject.mixpanel_result = "bogus"
      expect(subject).not_to be_valid
    end

    it "does not allow false" do
      subject.mixpanel_result = false
      expect(subject).not_to be_valid
    end

    it "does not allow 0" do
      subject.mixpanel_result = 0
      expect(subject).not_to be_valid
    end
  end

  describe ".to_hash" do
    it "is a hash of the split names to the variants" do
      split_1 = FactoryBot.create(:split, name: "split_1")
      split_2 = FactoryBot.create(:split, name: "split_2")
      FactoryBot.create(:assignment, split: split_1, variant: :hammer_time)
      FactoryBot.create(:assignment, split: split_2, variant: :touch_this)

      expect(described_class.to_hash).to eq(split_1: :hammer_time, split_2: :touch_this)
    end
  end

  describe ".for_presentation" do
    it "filters for one reason of underlying scopes (decision overrides)" do
      split = FactoryBot.create(:split, decided_at: Time.zone.now)
      assignment = FactoryBot.create(:assignment, split:, updated_at: 1.day.ago)

      expect(described_class.for_presentation).not_to include(assignment)
    end

    it "combines excluding_decision_overrides and for_active_splits (argless) with no app_build" do
      allow(described_class).to receive(:excluding_decision_overrides).and_call_original
      allow(described_class).to receive(:for_active_splits).and_call_original
      expect(described_class).not_to receive(:for_app_build)

      described_class.for_presentation

      expect(described_class).to have_received(:excluding_decision_overrides)
      expect(described_class).to have_received(:for_active_splits).with(no_args)
    end

    it "combines excluding_decision_overrides and for_app_build when app_build is provided" do
      app = FactoryBot.build_stubbed(:app)
      app_build = app.define_build(built_at: Time.zone.now, version: "1.0.0")
      allow(described_class).to receive(:excluding_decision_overrides).and_call_original
      allow(described_class).to receive(:for_app_build).and_call_original

      described_class.for_presentation(app_build:)

      expect(described_class).to have_received(:excluding_decision_overrides)
      expect(described_class).to have_received(:for_app_build).with(app_build)
    end
  end

  describe ".for_app_build" do
    it "combines for_active_splits, excluding_incomplete_features_for, and excluding_remote_kills_for" do
      app = FactoryBot.build_stubbed(:app)
      t = Time.zone.now
      app_build = app.define_build(built_at: t, version: "1.0.0")
      allow(described_class).to receive(:for_active_splits).and_call_original
      allow(described_class).to receive(:excluding_incomplete_features_for).and_call_original
      allow(described_class).to receive(:excluding_remote_kills_for).and_call_original

      described_class.for_app_build(app_build)

      expect(described_class).to have_received(:for_active_splits).with(as_of: t)
      expect(described_class).to have_received(:excluding_incomplete_features_for).with(app_build)
      expect(described_class).to have_received(:excluding_remote_kills_for).with(app_build)
    end
  end

  describe ".excluding_decision_overrides" do
    it "returns assignments to undecided splits" do
      split = FactoryBot.create(:split)
      assignment = FactoryBot.create(:assignment, split:)

      expect(described_class.excluding_decision_overrides).to include(assignment)
    end

    it "returns assignments more recent than the split decision" do
      split = FactoryBot.create(:split, decided_at: 1.week.ago)
      assignment = FactoryBot.create(:assignment, split:)

      expect(described_class.excluding_decision_overrides).to include(assignment)
    end

    it "doesn't return assignments simultaneous with split decision" do
      t = Time.zone.now
      split = FactoryBot.create(:split, decided_at: t)
      assignment = FactoryBot.create(:assignment, split:, updated_at: t)

      expect(described_class.excluding_decision_overrides).not_to include(assignment)
    end

    it "doesn't return assignments before split decision" do
      split = FactoryBot.create(:split, decided_at: Time.zone.now)
      assignment = FactoryBot.create(:assignment, split:, updated_at: 1.day.ago)

      expect(described_class.excluding_decision_overrides).not_to include(assignment)
    end
  end

  describe ".for_active_splits" do
    it "returns assignments for unfinished splits" do
      split = FactoryBot.create(:split)
      assignment = FactoryBot.create(:assignment, split:)

      expect(described_class.for_active_splits).to include(assignment)
    end

    it "doesn't return assignments for finished splits" do
      split = FactoryBot.create(:split, finished_at: Time.zone.now)
      assignment = FactoryBot.create(:assignment, split:)

      expect(described_class.for_active_splits).not_to include(assignment)
    end

    it "delegates to Split.active" do
      allow(Split).to receive(:active).and_call_original
      t = Time.zone.now

      described_class.for_active_splits(as_of: t)

      expect(Split).to have_received(:active).with(as_of: t)
    end
  end

  describe ".excluding_incomplete_features_for" do
    it "returns assignments to non-gates for which no app_feature_completion exists" do
      split = FactoryBot.create(:experiment)
      assignment = FactoryBot.create(:assignment, split:)
      app_build = split.owner_app.define_build(built_at: Time.zone.now, version: "1.0.1")

      expect(described_class.excluding_incomplete_features_for(app_build)).to include(assignment)
    end

    it "returns assignments for features completed before the provided version" do
      split = FactoryBot.create(:feature_gate)
      assignment = FactoryBot.create(:assignment, split:)
      app_feature_completion = FactoryBot.create(:app_feature_completion, feature_gate: split, version: "1.0.0")
      app_build = app_feature_completion.app.define_build(built_at: Time.zone.now, version: "1.0.1")

      expect(described_class.excluding_incomplete_features_for(app_build)).to include(assignment)
    end

    it "returns assignments for features completed at the provided version" do
      split = FactoryBot.create(:feature_gate)
      assignment = FactoryBot.create(:assignment, split:)
      app_feature_completion = FactoryBot.create(:app_feature_completion, feature_gate: split, version: "1.0.0")
      app_build = app_feature_completion.app.define_build(built_at: Time.zone.now, version: "1.0.0")

      expect(described_class.excluding_incomplete_features_for(app_build)).to include(assignment)
    end

    it "doesn't return assignments for features completed after the provided version" do
      split = FactoryBot.create(:feature_gate)
      assignment = FactoryBot.create(:assignment, split:)
      app_feature_completion = FactoryBot.create(:app_feature_completion, feature_gate: split, version: "1.0.0")
      app_build = app_feature_completion.app.define_build(built_at: Time.zone.now, version: "0.9.48")

      expect(described_class.excluding_incomplete_features_for(app_build)).not_to include(assignment)
    end

    it "returns assignments for features completed after the provided version if forced" do
      split = FactoryBot.create(:feature_gate)
      assignment = FactoryBot.create(:assignment, split:, force: true)
      app_feature_completion = FactoryBot.create(:app_feature_completion, feature_gate: split, version: "1.0.0")
      app_build = app_feature_completion.app.define_build(built_at: Time.zone.now, version: "0.9.48")

      expect(described_class.excluding_incomplete_features_for(app_build)).to include(assignment)
    end

    it "doesn't return assignments for features completed on a different app" do
      split = FactoryBot.create(:feature_gate)
      assignment = FactoryBot.create(:assignment, split:)
      FactoryBot.create(:app_feature_completion, feature_gate: split, version: "1.0.0")
      other_app = FactoryBot.create(:app)
      app_build = other_app.define_build(built_at: Time.zone.now, version: "1.0.0")

      expect(described_class.excluding_incomplete_features_for(app_build)).not_to include(assignment)
    end

    it "returns assignments for features never completed if forced" do
      split = FactoryBot.create(:feature_gate)
      assignment = FactoryBot.create(:assignment, split:, force: true)
      app = FactoryBot.create(:app)
      app_build = app.define_build(built_at: Time.zone.now, version: "1.0.0")

      expect(described_class.excluding_incomplete_features_for(app_build)).to include(assignment)
    end
  end

  describe ".excluding_remote_kills_for" do
    it "returns assignments for which no remote kill exists" do
      split = FactoryBot.create(:split)
      assignment = FactoryBot.create(:assignment, split:, force: true)
      app = FactoryBot.create(:app)
      app_build = app.define_build(built_at: Time.zone.now, version: "1.0.0")

      expect(described_class.excluding_remote_kills_for(app_build)).to include(assignment)
    end

    it "returns assignments for non-overlapping remote kills" do
      split = FactoryBot.create(:split)
      assignment = FactoryBot.create(:assignment, split:, force: true)
      app = FactoryBot.create(:app)
      FactoryBot.create(:app_remote_kill, split:, app:, first_bad_version: "1.1", fixed_version: "1.2")
      app_build = app.define_build(built_at: Time.zone.now, version: "1.0.0")

      expect(described_class.excluding_remote_kills_for(app_build)).to include(assignment)
    end

    it "doesn't return assignments for overlapping remote kills, even if forced and more recent" do
      split = FactoryBot.create(:split)
      app = FactoryBot.create(:app)
      FactoryBot.create(:app_remote_kill, split:, app:, first_bad_version: "0.9", fixed_version: "1.2")
      assignment = FactoryBot.create(:assignment, split:, force: true)
      app_build = app.define_build(built_at: Time.zone.now, version: "1.0.0")

      expect(described_class.excluding_remote_kills_for(app_build)).not_to include(assignment)
    end

    it "is backed by Split.arel_excluding_remote_kills_for" do
      app = FactoryBot.create(:app)
      app_build = app.define_build(built_at: Time.zone.now, version: "1.0.0")
      allow(Split).to receive(:arel_excluding_remote_kills_for).and_call_original

      described_class.excluding_remote_kills_for(app_build)

      expect(Split).to have_received(:arel_excluding_remote_kills_for).with(app_build, any_args)
    end
  end

  describe "#create_previous_assignment" do
    it "passes back a true force value" do
      assignment = FactoryBot.create(:assignment, force: true)
      previous_assignment = assignment.create_previous_assignment!(Time.zone.now)

      expect(previous_assignment).to be_a PreviousAssignment
      expect(previous_assignment.force).to be(true)
    end

    it "passes back a false force value" do
      assignment = FactoryBot.create(:assignment, force: false)
      previous_assignment = assignment.create_previous_assignment!(Time.zone.now)

      expect(previous_assignment).to be_a PreviousAssignment
      expect(previous_assignment.force).to be(false)
    end
  end
end
