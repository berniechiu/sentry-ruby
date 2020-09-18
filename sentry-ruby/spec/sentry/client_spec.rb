require 'spec_helper'

class ExceptionWithContext < StandardError
  def sentry_context
    { extra: {
      'context_event_key' => 'context_value',
      'context_key' => 'context_value'
    } }
  end
end

RSpec.describe Sentry::Client do
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
    end
  end
  let(:client) { Sentry::Client.new(configuration) }
  subject { client }

  before do
    @fake_time = Time.now
    allow(Time).to receive(:now).and_return @fake_time
  end

  describe "#generate_auth_header" do
    it "generates an auth header" do
      expect(client.send(:generate_auth_header)).to eq(
        "Sentry sentry_version=5, sentry_client=sentry-ruby/#{Sentry::VERSION}, sentry_timestamp=#{@fake_time.to_i}, " \
        "sentry_key=12345, sentry_secret=67890"
      )
    end

    it "generates an auth header without a secret (Sentry 9)" do
      configuration.server = "https://66260460f09b5940498e24bb7ce093a0@sentry.io/42"

      expect(client.send(:generate_auth_header)).to eq(
        "Sentry sentry_version=5, sentry_client=sentry-ruby/#{Sentry::VERSION}, sentry_timestamp=#{@fake_time.to_i}, " \
        "sentry_key=66260460f09b5940498e24bb7ce093a0"
      )
    end
  end

  # it "generates a message with exception" do
  #   event = Sentry.capture_exception(ZeroDivisionError.new("divided by 0")).to_hash
  #   expect(client.send(:get_message_from_exception, event)).to eq("ZeroDivisionError: divided by 0")
  # end

  # it "generates a message without exception" do
  #   event = Sentry.capture_message("this is an STDOUT transport test").to_hash
  #   expect(client.send(:get_message_from_exception, event)).to eq(nil)
  # end

  # describe "#send_event" do
  #   let(:event) { subject.event_from_exception(ZeroDivisionError.new("divided by 0")) }

  #   context "when success" do
  #     before do
  #       allow(client.transport).to receive(:send_event)
  #     end

  #     it "sends Event object" do
  #       expect(client).not_to receive(:failed_send)

  #       expect(client.send_event(event)).to eq(event.to_hash)
  #     end

  #     it "sends Event hash" do
  #       expect(client).not_to receive(:failed_send)

  #       expect(client.send_event(event.to_json_compatible)).to eq(event.to_json_compatible)
  #     end
  #   end

  #   context "when failed" do
  #     let(:logger) { spy }

  #     before do
  #       configuration.logger = logger
  #       allow(client.transport).to receive(:send_event).and_raise(StandardError)

  #       expect(logger).to receive(:warn).exactly(2)
  #     end

  #     it "sends Event object" do
  #       expect(client.send_event(event)).to eq(nil)
  #     end

  #     it "sends Event hash" do
  #       expect(client.send_event(event.to_json_compatible)).to eq(nil)
  #     end
  #   end
  # end

  describe "#transport" do
    context "when scheme is not set" do
      it "returns HTTP transport object" do
        expect(client.transport).to be_a(Sentry::Transports::HTTP)
      end
    end

    context "when scheme is http" do
      before do
        configuration.scheme = "http"
      end

      it "returns HTTP transport object" do
        expect(client.transport).to be_a(Sentry::Transports::HTTP)
      end
    end

    context "when scheme is https" do
      before do
        configuration.scheme = "https"
      end

      it "returns HTTP transport object" do
        expect(client.transport).to be_a(Sentry::Transports::HTTP)
      end
    end

    context "when scheme is dummy" do
      before do
        configuration.scheme = "dummy"
      end

      it "returns Dummy transport object" do
        expect(client.transport).to be_a(Sentry::Transports::Dummy)
      end
    end

    context "when scheme is stdout" do
      before do
        configuration.scheme = "stdout"
      end

      it "returns Stdout transport object" do
        expect(client.transport).to be_a(Sentry::Transports::Stdout)
      end
    end
  end

  describe "#event_from_exception" do
    before do
      configuration.scheme = "dummy"
    end

    it "proceses string message correctly" do
      event = subject.event_from_exception(ExceptionWithContext.new, message: "MSG")
      expect(event.message).to eq("MSG")
    end

    it "slices long string message" do
      event = subject.event_from_exception(ExceptionWithContext.new, message: "MSG" * 3000)
      expect(event.message.length).to eq(8192)
    end

    it "converts non-string message into string" do
      expect(configuration.logger).to receive(:debug).with("You're passing a non-string message")

      event = subject.event_from_exception(ExceptionWithContext.new, message: { foo: "bar" })
      expect(event.message).to eq("{:foo=>\"bar\"}")
    end

    context 'merging exception context' do
      let(:hash) do
        event = subject.event_from_exception(
          ExceptionWithContext.new,
          message: "MSG",
          extra: {
            'context_event_key' => 'event_value',
            'event_key' => 'event_value'
          }
        )
        event.to_hash
      end

      it 'prioritizes event context over request context' do
        expect(hash[:extra]['context_event_key']).to eq('event_value')
        expect(hash[:extra]['context_key']).to eq('context_value')
        expect(hash[:extra]['event_key']).to eq('event_value')
      end
    end
  end
end