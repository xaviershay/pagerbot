require_relative('../../_lib')
require_relative './mocked_pagerduty_class'

class ActionManager < Critic::MockedPagerDutyTest
  def event_data(opts={nick: "karl"})
    opts
  end

  before do 
    @manager = PagerBot::ActionManager.new(
      :pagerduty => @pagerduty_settings,
      :bot => @bot_settings)
    @pagerduty = @manager.instance_variable_get("@pagerduty")

    @fake_schedule = {
      schedule: {
        id: "PRIMAR1",
        name: "Primary",
        time_zone: "Eastern Time (US & Canada)",
        today: "2013-03-26",
        escalation_policies: [{
          name: "Another Escalation Policy",
          id: "P08G4S6"
        }],
        final_schedule: {
          rendered_schedule_entries: [{
            user: {
              name: "Karl-Aksel Puulmann",
              id: "P123456"
            },
            end: "2014-07-28T19:00:00-07:00",
            start: "2014-07-28T15:00:00-07:00"
          }],
          name: "Final Schedule"
        }
      }
    }

    @fake_service = {
      type: "generic_email",
      id: "PFAKESRV",
      name: "AnotherService",
      service_url: "/services/P4UQ4A3",
      service_key: "another-service@subdomain.pagerduty.com",
    }
  end

  describe 'dispatch' do
    it 'convert returned strings => {:message => string}' do
      val = @manager.dispatch({type: 'help'}, event_data)
      assert(val.is_a?(Hash))
      assert_includes(val, :message)
    end

    it 'should replace spaces with underscores, find no such command' do
      val = @manager.dispatch({type: 'no such command'}, event_data)
      assert_includes(val[:message], "ask for help")
    end
  end

  describe 'actions:' do
    describe 'list schedules' do
      it 'should list all known schedules' do
        val = @manager.dispatch({type: 'list-schedules'}, event_data)[:private_message]
        assert_includes(val, "primary, primary breakage")
        assert_includes(val, "sys, sys run")
      end
    end

    describe 'when is someone on schedule' do
      before do
        @fake_oncall_info = {
          user: {
            color: "crimson",
            email: "karl@stripe.com",
            name: "Karl-Aksel Puulmann",
            id: "P123456"
          },
          end: "2014-08-18T10:00:00-07:00",
          start: Time.now.to_s
        }
      end

      it 'person not on schedule' do
        @pagerduty.expects(:next_oncall)
          .with("P123456", "PRIMAR1")

        response = @manager.lookup_person({
          :person => "i",
          :schedule => "primary"
        }, event_data).fetch(:message)

        assert_equal("Karl-Aksel Puulmann is not scheduled to go on Primary breakage", response)
      end

      it 'person currently on schedule' do
        @pagerduty.expects(:next_oncall)
          .with('P123456', 'PRIMAR1')
          .returns @fake_oncall_info

        response = @manager.lookup_person({
          :person => "karl",
          :schedule => "primary"
        }, event_data)

        assert_equal("Karl-Aksel Puulmann is on Primary breakage now", response.fetch(:message))
      end
    end

    describe 'who is on schedule X' do
      it 'should work on happy path' do
        @pagerduty.expects(:get)
          .with { |url, _, _| url == '/schedules/PRIMAR1' }
          .returns(@fake_schedule)

        query = {schedule: "primary", time: "3 PM"}
        val = @manager.lookup_time(query, event_data).fetch(:message)
        # answer from perspective of the person. 
        # query was from GMT-7, which adds 7 hours to the original time
        assert_equal("Karl-Aksel Puulmann is on call at 2014-07-28 22:00:00 +0000.", val)
      end

      it 'noone on schedule' do
        @fake_schedule[:schedule][:final_schedule][:rendered_schedule_entries] = []
        @pagerduty.expects(:get)
          .with { |url, _, _| url == '/schedules/PRIMAR1' }
          .returns(@fake_schedule)

        query = {schedule: "primary", time: "3 PM"}
        val = @manager.lookup_time(query, event_data).fetch(:message)

        assert_equal("No-one is on call then for Primary breakage.", val)
      end
    end

    describe 'help' do
      it 'should list help, manual, list, people' do
        help_text = @manager.dispatch({type: 'help'}, event_data)[:message]

        assert_includes(help_text, 'help')
        assert_includes(help_text, 'manual')
        assert_includes(help_text, 'list')
        assert_includes(help_text, 'people')
      end

      it 'should include help link if provided' do
        @bot_settings[:help_message] = "https://example.com/help"
        @manager = PagerBot::ActionManager.new(
          :pagerduty => @pagerduty_settings,
          :bot => @bot_settings)
        @pagerduty = @manager.instance_variable_get("@pagerduty")

        help_text = @manager.dispatch({type: 'help'}, event_data)[:message]

        assert_includes(help_text, 'https://example.com/help')
      end
    end

    describe 'manual' do
      it 'manual should list manual' do
        manual_text = @manager.dispatch({type: 'manual'}, event_data)[:private_message]

        assert_includes(manual_text, 'Get more detailed command usage')
      end
    end
  end
end
