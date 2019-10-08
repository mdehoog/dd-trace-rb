require 'spec_helper'

require 'ddtrace/configuration/settings'

RSpec.describe Datadog::Configuration::Settings do
  subject(:configuration) { described_class.new(registry: registry) }
  let(:registry) { Datadog::Contrib::Registry.new }

  # TODO: Extract integration behavior to `contrib`
  describe '#use' do
    subject(:result) { configuration.use(name, options) }
    let(:name) { :example }
    let(:integration) { double('integration') }
    let(:options) { {} }

    before(:each) do
      registry.add(name, integration)
    end

    context 'for a generic integration' do
      before(:each) do
        expect(integration).to receive(:configure).with(:default, options).and_return([])
        expect(integration).to receive(:patch).and_return(true)
      end

      it { expect { result }.to_not raise_error }
    end

    context 'for an integration that includes Datadog::Contrib::Integration' do
      let(:patcher_module) do
        stub_const('Patcher', Module.new do
          include Datadog::Contrib::Patcher

          def self.patch
            true
          end
        end)
      end

      let(:integration_class) do
        patcher_module

        Class.new do
          include Datadog::Contrib::Integration

          def self.version
            Gem::Version.new('0.1')
          end

          def patcher
            Patcher
          end
        end
      end

      let(:integration) do
        integration_class.new(name)
      end

      context 'which is provided only a name' do
        it do
          expect(integration).to receive(:configure).with(:default, {})
          configuration.use(name)
        end
      end

      context 'which is provided a block' do
        it do
          expect(integration).to receive(:configure).with(:default, {}).and_call_original
          expect { |b| configuration.use(name, options, &b) }.to yield_with_args(
            a_kind_of(Datadog::Contrib::Configuration::Settings)
          )
        end
      end
    end
  end

  describe '#tracer' do
    let(:tracer) { Datadog::Tracer.new }
    let(:debug_state) { tracer.class.debug_logging }
    let(:custom_log) { Logger.new(STDOUT) }

    context 'given some settings' do
      before(:each) do
        @original_log = tracer.class.log

        configuration.tracer(
          enabled: false,
          debug: !debug_state,
          log: custom_log,
          hostname: 'tracer.host.com',
          port: 1234,
          env: :config_test,
          tags: { foo: :bar },
          instance: tracer
        )
      end

      after(:each) do
        tracer.class.debug_logging = debug_state
        tracer.class.log = @original_log
      end

      it 'applies settings correctly' do
        expect(tracer.enabled).to be false
        expect(debug_state).to be false
        expect(Datadog::Tracer.log).to eq(custom_log)
        expect(tracer.writer.transport.current_api.adapter.hostname).to eq('tracer.host.com')
        expect(tracer.writer.transport.current_api.adapter.port).to eq(1234)
        expect(tracer.tags[:env]).to eq(:config_test)
        expect(tracer.tags[:foo]).to eq(:bar)
      end
    end

    it 'acts on the default tracer' do
      previous_state = Datadog.tracer.enabled
      configuration.tracer(enabled: !previous_state)
      expect(Datadog.tracer.enabled).to eq(!previous_state)
      configuration.tracer(enabled: previous_state)
      expect(Datadog.tracer.enabled).to eq(previous_state)
    end
  end

  describe '#[]' do
    context 'when the integration doesn\'t exist' do
      it do
        expect { configuration[:foobar] }.to raise_error(
          Datadog::Contrib::Extensions::Configuration::Settings::InvalidIntegrationError
        )
      end
    end
  end
end
