require 'sidekiq/testing'
require 'active_support/core_ext/hash/indifferent_access'

module RSpec
  # An includable module that provides `enqueue_sidekiq_job` matcher
  module EnqueueSidekiqJob
    # Checks if a certain job was enqueued in a block.
    #
    # @example
    #   expect { AwesomeWorker.perform_async }
    #     .to enqueue_sidekiq_job(AwesomeWorker)
    #
    # @example Matching on arguments
    #   expect { AwesomeWorker.perform_async(42, 'David')
    #     .to enqueue_sidekiq_job(AwesomeWorker).with(42, 'David')
    #
    # @example Matching time with `at`
    #   time = 5.minutes.from_now
    #   expect { AwesomeWorker.perform_at(time) }
    #     .to enqueue_sidekiq_job(AwesomeWorker).at(time)
    #
    # @example Matching time relatively with `in`
    #   interval = 5.minutes
    #   expect { AwesomeWorker.perform_in(interval) }
    #     .to enqueue_sidekiq_job(AwesomeWorker).in(5.minutes)
    #
    # @example Matching counts
    #   expect {
    #     AwesomeWorker.perform_async
    #     AwesomeWorker.perform_async
    #   }.to enqueue_sidekiq_job(AwesomeWorker).twice
    #
    # @example Matching counts - more
    #   enqueue_sidekiq_job(AwesomeWorker).once
    #   enqueue_sidekiq_job(AwesomeWorker).twice
    #   enqueue_sidekiq_job(AwesomeWorker).exactly(3).times
    #
    def enqueue_sidekiq_job(worker_class)
      Matcher.new(worker_class)
    end

    # @private
    class Matcher
      include RSpec::Matchers::Composable

      def initialize(worker_class)
        @worker_class = worker_class
        @expected_count = nil
      end

      def with(*expected_arguments, &block)
        if block
          raise ArgumentError, 'setting arguments with block is not supported' if expected_arguments.any?

          @expected_arguments = block
        else
          @expected_arguments = normalize_arguments(expected_arguments)
        end

        self
      end

      def at(timestamp)
        raise 'setting expecations with both `at` and `in` is not supported' if @expected_in

        @expected_at = timestamp
        self
      end

      def in(interval)
        raise 'setting expecations with both `at` and `in` is not supported' if @expected_at

        @expected_in = interval
        self
      end

      def times
        self
      end

      def exactly(times)
        @expected_count = times
        self
      end

      def once
        exactly(1).times
      end

      def twice
        exactly(2).times
      end

      def matches?(block)
        filter(enqueued_in_block(block)).count == (expected_count || 1)
      end

      def does_not_match?(block)
        raise 'counts are not supported with negation' if expected_count

        filter(enqueued_in_block(block)).none?
      end

      def failure_message
        message = ["expected to enqueue #{worker_class} job"]
        message << "  arguments: #{expected_arguments}" if expected_arguments
        message << "  in: #{expected_in.inspect}" if expected_in
        message << "  at: #{expected_at}" if expected_at
        message << "  exactly #{expected_count} times" if expected_count
        message.join("\n")
      end

      def failure_message_when_negated
        message = ["expected not to enqueue #{worker_class} job"]
        message << "  arguments: #{expected_arguments}" if expected_arguments
        message << "  in: #{expected_in.inspect}" if expected_in
        message << "  at: #{expected_at}" if expected_at
        message << "  exactly #{expected_count} times" if expected_count
        message.join("\n")
      end

      def supports_block_expectations?
        true
      end

      def supports_value_expectations?
        false
      end

      private

      def normalize_arguments(arguments)
        if arguments.last.is_a?(Hash)
          options = arguments.pop
          arguments.push(options.with_indifferent_access)
        end

        arguments
      end

      def enqueued_in_block(block)
        before = @worker_class.jobs.dup
        result = block.call

        if @expected_arguments.is_a?(Proc)
          arguments = @expected_arguments.call(result)
          raise '`with` block is expected to return an Array' unless arguments.is_a?(Array)

          @expected_arguments = normalize_arguments(arguments)
        end

        @worker_class.jobs - before
      end

      def filter(jobs)
        jobs = jobs.select { |job| timestamps_match_rounded_to_seconds?(job['at']) } if expected_at
        jobs = jobs.select { |job| intervals_match_rounded_to_seconds?(job['at']) } if expected_in
        jobs = jobs.select { |job| values_match?(expected_arguments, job['args']) } if expected_arguments
        jobs
      end

      # Due to zero nsec precision of `Time.now` (and therefore `5.minutes.from_now`) on
      # some platforms, and lossy Sidekiq serialization that uses `.to_f` on timestamps,
      # values won't match unless rounded.
      # Rounding to whole seconds is sub-optimal but simple.
      def timestamps_match_rounded_to_seconds?(actual)
        return false if actual.nil?

        actual_time = Time.at(actual)
        values_match?(expected_at, actual_time) ||
          expected_at.to_i == actual_time.to_i
      end

      def intervals_match_rounded_to_seconds?(actual)
        return false if actual.nil?

        actual_time = Time.at(actual)
        expected_in.from_now.to_i == actual_time.to_i
      end

      attr_reader :worker_class, :expected_arguments, :expected_at, :expected_in, :expected_count
    end

    private_constant :Matcher
  end
end

RSpec.configure do |config|
  config.include RSpec::EnqueueSidekiqJob
end
