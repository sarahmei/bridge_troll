require 'rails_helper'

describe Event do
  before do
    @user = create(:user)
  end

  it { should belong_to(:location) }
  it { should have_many(:rsvps) }
  it { should have_many(:event_sessions) }
  it { should validate_numericality_of(:student_rsvp_limit) }

  it { should validate_presence_of(:title) }

  it "validates that there is at least one event session" do
    event = create(:event)
    event.event_sessions.destroy_all
    event.should have(1).error_on(:event_sessions)

    event.event_sessions << build(:event_session)
    event.should be_valid
  end

  it "sorts event_sessions by ends_at" do
    event = create(:event)

    session2 = event.event_sessions.first
    session2.update_attributes(starts_at: Time.now, ends_at: 1.hour.from_now)
    session3 = create(:event_session, event: event, starts_at: 20.days.from_now, ends_at: 21.days.from_now)
    session1 = create(:event_session, event: event)
    session1.update_attributes(starts_at: 10.days.ago, ends_at: 9.days.ago)

    event.reload.event_sessions.should == [session1, session2, session3]
  end

  it "must have a time zone" do
    event = build(:event, :time_zone => nil)
    event.should have(1).error_on(:time_zone)
  end

  it "must have a valid time zone" do
    event = build(:event, :time_zone => "xxx")
    event.should have(1).error_on(:time_zone)

    event = build(:event, :time_zone => 'Hawaii')
    event.should have(0).errors
  end

  describe "updating an event" do
    describe 'decreasing the student RSVP limit' do
      before do
        @event = create(:event, student_rsvp_limit: 5)
        2.times { create(:student_rsvp, event: @event) }
        create(:volunteer_rsvp, event: @event)
        @event.reload
      end

      it 'is allowed if the new limit is greater than or equal to the current number of attendees' do
        @event.update_attributes(student_rsvp_limit: 2)
        @event.should have(0).errors_on(:student_rsvp_limit)
      end

      it 'is disallowed if anyone would be kicked out of the workshop' do
        @event.update_attributes(student_rsvp_limit: 1)
        @event.should have(1).errors_on(:student_rsvp_limit)
      end
    end

    it "does allow student_rsvp_limit to be increased" do
      event = create(:event, student_rsvp_limit: 10)
      event.update_attributes(student_rsvp_limit: 20)
      event.should have(0).errors_on(:student_rsvp_limit)
    end

    it "reorders the waitlist" do
      event = create(:event, student_rsvp_limit: 10)
      event.should_receive(:reorder_waitlist!)
      event.update_attributes(student_rsvp_limit: 200)
    end
  end

  describe '#location_name' do
    context 'location is set' do
      let(:event) { build(:event, location: build(:location, name: 'FUNZONE!')) }
      it 'returns the name of the location' do
        event.location_name.should eq('FUNZONE!')
      end
    end

    context 'location is nil' do
      let(:event) { build(:event, location: nil) }
      it 'returns an empty string' do
        event.location_name.should eq('')
      end
    end
  end

  describe '#rsvps_with_childcare' do
    it 'includes all rsvps with childcare requested' do
      event = create(:event)
      event.rsvps_with_childcare.should == event.student_rsvps.needs_childcare + event.volunteer_rsvps.needs_childcare
    end
  end

  describe '#starts_at, #ends_at' do
    it 'populates from the event_session when creating an event+session together' do
      event = Event.create(
        title: "Amazingly Sessioned Event",
        details: "This is note in the details attribute.",
        time_zone: "Hawaii",
        published: true,
        student_rsvp_limit: 100,
        course_id: Course::RAILS.id,
        volunteer_details: "I am some details for volunteers.",
        student_details: "I am some details for students.",
        event_sessions_attributes: {
          "0" => {
            name: "My Amazing Session",
            required_for_students: "1",
            "starts_at(1i)" => "2015",
            "starts_at(2i)" => "01",
            "starts_at(3i)" => "12",
            "starts_at(4i)" => "15",
            "starts_at(5i)" => "15",
            "ends_at(1i)" => "2015",
            "ends_at(2i)" => "01",
            "ends_at(3i)" => "12",
            "ends_at(4i)" => "17",
            "ends_at(5i)" => "45"
          }
        }
      )
      event.starts_at.should == event.event_sessions.first.starts_at
      event.ends_at.should == event.event_sessions.first.ends_at
    end
  end

  describe "#volunteer?" do
    let(:event) { create(:event) }

    it "is true when a user is volunteering at an event" do
      create(:rsvp, :user => @user, :event => event)
      event.volunteer?(@user).should == true
    end

    it "is false when a user is not volunteering at an event" do
      event.volunteer?(@user).should == false
    end
  end

  describe "#waitlisted_student?" do
    let(:event) { create(:event) }

    it "returns true when a user is a waitlisted student" do
      create(:student_rsvp, :user => @user, :event => event, waitlist_position: 1)
      event.waitlisted_student?(@user).should == true
    end

    it "returns false when a user is not waitlisted" do
      create(:student_rsvp, :user => @user, :event => event)
      event.waitlisted_student?(@user).should == false
    end
  end

  describe "#rsvp_for_user" do
    it "should return the rsvp for a user" do
      event = create(:event)
      event.rsvp_for_user(@user).should == event.rsvps.find_by_user_id(@user.id)
    end
  end

  describe ".upcoming" do
    before do
      @event_past = create(:event)
      @event_past.event_sessions.first.update_attributes(
        starts_at: 4.weeks.ago, ends_at: 3.weeks.ago
      )

      @event_future = create(:event)
      @event_future.event_sessions.first.update_attributes(
        starts_at: 3.weeks.from_now, ends_at: 4.weeks.from_now
      )

      @event_in_progress = create(:event)
      @event_in_progress.event_sessions.first.update_attributes(
        starts_at: 2.days.ago, ends_at: 2.days.from_now
      )
    end

    it "includes events that have not already ended" do
      Event.upcoming.to_a.map(&:id).should == [@event_in_progress.id, @event_future.id]
    end
  end

  describe ".published_or_organized_by" do
    before do
      @published_event = create(:event, title: 'published event', published: true)
      @unpublished_event = create(:event, title: 'unpublished event', published: false)
      @organized_event = create(:event, title: 'organized event', published: false)
    end

    context "when a user is not provided" do
      it 'returns only published events' do
        Event.published_or_organized_by.should =~ [@published_event]
      end
    end

    context "when the organizer of an event is provided" do
      before do
        @organizer = create(:user)
        @organized_event.organizers << @organizer
      end

      it "returns published events and the organizer's event" do
        Event.published_or_organized_by(@organizer).should =~ [@published_event, @organized_event]
      end
    end

    context "when an admin is provided" do
      before do
        @admin = create(:user, admin: true)
      end

      it "returns all events" do
        Event.published_or_organized_by(@admin).should =~ [@published_event, @unpublished_event, @organized_event]
      end
    end
  end

  describe "#details" do
    it "has default content" do
      Event.new.details.should =~ /Workshop Description/
    end
  end

  describe "#at_limit?" do
    context "when the event has a limit" do
      let(:event) { create(:event, student_rsvp_limit: 2) }

      it 'is true when the limit is exceeded' do
        expect {
          3.times { create(:student_rsvp, event: event) }
        }.to change { event.reload.at_limit? }.from(false).to(true)
      end
    end

    context "when the event has no limit (historical events)" do
      let(:event) { create(:event, student_rsvp_limit: nil, meetup_student_event_id: 901, meetup_volunteer_event_id: 902) }

      it 'is false' do
        event.should_not be_at_limit
      end
    end
  end

  describe "#reorder_waitlist!" do
    before do
      @event = create(:event, student_rsvp_limit: 2)
      @confirmed1 = create(:student_rsvp, event: @event)
      @confirmed2 = create(:student_rsvp, event: @event)
      @waitlist1 = create(:student_rsvp, event: @event, waitlist_position: 1)
      @waitlist2 = create(:student_rsvp, event: @event, waitlist_position: 2)
      @waitlist3 = create(:student_rsvp, event: @event, waitlist_position: 3)
    end

    context "when the limit has increased" do
      before do
        @event.update_attribute(:student_rsvp_limit, 4)
      end

      it "promotes people on the waitlist into available slots when the limit increases" do
        @event.reorder_waitlist!
        @event.reload

        @event.student_rsvps.count.should == 4
        @event.student_waitlist_rsvps.count.should == 1
      end
    end

    context "when a confirmed rsvp has been destroyed" do
      before do
        @confirmed1.destroy
        @event.reorder_waitlist!
      end

      it 'promotes a waitlisted user to confirmed when the rsvp is destroyed' do
        @waitlist1.reload.waitlist_position.should be_nil
        @waitlist2.reload.waitlist_position.should == 1
        @waitlist3.reload.waitlist_position.should == 2
      end
    end

    context "when a waitlisted rsvp has been destroyed" do
      before do
        @waitlist1.destroy
        @event.reorder_waitlist!
      end

      it 'reorders the waitlist when the rsvp is destroyed' do
        @waitlist2.reload.waitlist_position.should == 1
        @waitlist3.reload.waitlist_position.should == 2
      end
    end
  end

  describe "#students" do
    before do
      @event = create(:event)
      @volunteer_rsvp = create(:volunteer_rsvp, event: @event, role: Role::VOLUNTEER)
      @confirmed_rsvp = create(:student_rsvp, event: @event, role: Role::STUDENT)
      @waitlist_rsvp = create(:student_rsvp, event: @event, role: Role::STUDENT, waitlist_position: 1)
    end

    it 'should only include non-waitlisted students' do
      @event.students.should == [@confirmed_rsvp.user]
    end
  end

  describe "#rsvps_with_checkins" do
    before do
      @event = create(:event)
      @first_session = @event.event_sessions.first
      @first_session.update_attributes(ends_at: 6.months.from_now)

      @last_session = create(:event_session, event: @event, ends_at: 1.year.from_now)

      @rsvp1 = create(:rsvp, event: @event)
      create(:rsvp_session, event_session: @first_session, rsvp: @rsvp1, checked_in: true)

      @rsvp2 = create(:rsvp, event: @event)
      create(:rsvp_session, event_session: @last_session, rsvp: @rsvp2)

      @rsvp3 = create(:rsvp, event: @event)
      create(:rsvp_session, event_session: @last_session, rsvp: @rsvp3, checked_in: true)

      @event.reload
    end

    it 'counts attendances for the last session' do
      attendee_rsvp_data = @event.rsvps_with_checkins
      attendee_rsvp_data.length.should == 3

      workshop_attendees = attendee_rsvp_data.map { |rsvp| [rsvp['id'], rsvp['checked_in_session_ids']] }
      workshop_attendees.should =~ [
        [@rsvp1.id, [@first_session.id]],
        [@rsvp2.id, []],
        [@rsvp3.id, [@last_session.id]]
      ]
    end
  end

  describe "#checkin_counts" do
    before do
      @event = create(:event)
      @event.update_attribute(:student_rsvp_limit, 2)
      @session1 = @event.event_sessions.first
      @session2 = create(:event_session, event: @event)

      def deep_copy(o)
        Marshal.load(Marshal.dump(o))
      end

      expectation = {
        Role::VOLUNTEER.id => {
          @session1.id => [],
          @session2.id => []
        },
        Role::STUDENT.id => {
          @session1.id => [],
          @session2.id => []
        }
      }
      @rsvps = deep_copy(expectation)
      @checkins = deep_copy(expectation)

      def add_session_rsvp(rsvp, session, checked_in)
        create(:rsvp_session, rsvp: rsvp, event_session: session, checked_in: checked_in)
        @rsvps[rsvp.role.id][session.id] << rsvp
        @checkins[rsvp.role.id][session.id] << rsvp if checked_in
      end

      rsvp1 = create(:volunteer_rsvp, event: @event)
      add_session_rsvp(rsvp1, @session1, true)
      add_session_rsvp(rsvp1, @session2, true)

      rsvp2 = create(:volunteer_rsvp, event: @event)
      add_session_rsvp(rsvp2, @session1, true)
      add_session_rsvp(rsvp2, @session2, false)

      rsvp3 = create(:volunteer_rsvp, event: @event)
      add_session_rsvp(rsvp3, @session1, true)

      rsvp4 = create(:student_rsvp, event: @event)
      add_session_rsvp(rsvp4, @session2, true)

      rsvp5 = create(:student_rsvp, event: @event)
      add_session_rsvp(rsvp5, @session2, true)

      waitlisted = create(:student_rsvp, event: @event, waitlist_position: 1)
      create(:rsvp_session, rsvp: waitlisted, event_session: @session2, checked_in: false)
    end

    it "sends checked in user counts to the view" do
      checkin_counts = @event.checkin_counts
      checkin_counts[Role::VOLUNTEER.id][:rsvp].should == {
        @session1.id => @rsvps[Role::VOLUNTEER.id][@session1.id].length,
        @session2.id => @rsvps[Role::VOLUNTEER.id][@session2.id].length
      }
      checkin_counts[Role::VOLUNTEER.id][:checkin].should == {
        @session1.id => @checkins[Role::VOLUNTEER.id][@session1.id].length,
        @session2.id => @checkins[Role::VOLUNTEER.id][@session2.id].length
      }

      checkin_counts[Role::STUDENT.id][:rsvp].should == {
        @session1.id => @rsvps[Role::STUDENT.id][@session1.id].length,
        @session2.id => @rsvps[Role::STUDENT.id][@session2.id].length
      }
      checkin_counts[Role::STUDENT.id][:checkin].should == {
        @session1.id => @checkins[Role::STUDENT.id][@session1.id].length,
        @session2.id => @checkins[Role::STUDENT.id][@session2.id].length
      }
    end
  end

  describe "waitlists" do
    before do
      @event = create(:event, student_rsvp_limit: 2)
      @confirmed_rsvp = create(:student_rsvp, event: @event, role: Role::STUDENT)
      @waitlist_rsvp = create(:student_rsvp, event: @event, role: Role::STUDENT, waitlist_position: 1)
    end

    it "returns only confirmed rsvps in #student_rsvps" do
      @event.student_rsvps.should == [@confirmed_rsvp]
    end

    it "returns only waitlisted rsvps in #student_waitlist_rsvps" do
      @event.student_waitlist_rsvps.should == [@waitlist_rsvp]
    end
  end

  describe "methods for presenting dietary restrictions" do
    before do
      @event = create(:event)
      @rsvp = create(:rsvp, event: @event)
      @rsvp2 = create(:rsvp, event: @event, dietary_info: "No sea urchins")
      create(:dietary_restriction, restriction: "gluten-free", rsvp: @rsvp)
      create(:dietary_restriction, restriction: "vegan", rsvp: @rsvp)
      create(:dietary_restriction, restriction: "vegan", rsvp: @rsvp2)
    end

    describe "#dietary_restrictions_totals" do
      it "should return the total for each dietary restrictions" do
        @event.dietary_restrictions_totals.should == { "gluten-free" => 1, "vegan" => 2 }
      end
    end

    describe "#other_dietary_restrictions" do
      it "should returns an array of dietary restrictions" do
        expect(@event.other_dietary_restrictions).to eq(["Paleo", "No sea urchins"])
      end
    end

  end
end
