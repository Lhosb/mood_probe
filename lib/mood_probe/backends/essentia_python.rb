require "json"
require "open3"
require "pathname"
require "timeout"

module MoodProbe
  module Backends
    class EssentiaPython
      STARTUP_GRACE = 10
      SCRIPT_PATH = Pathname(__dir__).join("../../../python/mood_probe_extract.py").expand_path

      class CommandTimeout < StandardError; end
      class CommandLaunchError < StandardError; end

      class CommandRunner
        Result = Struct.new(:stdout, :stderr, :exitstatus, :termsig, keyword_init: true)

        def call(command, timeout:)
          stdout_text, stderr_text, status = capture(command, timeout:)
          result(stdout_text, stderr_text, status)
        rescue Errno::ENOENT, Errno::EACCES => e
          raise CommandLaunchError, e.message
        end

        private

        def capture(command, timeout:)
          stdout_text = stderr_text = nil
          status = nil

          Open3.popen3(*command, pgroup: true) do |stdin, stdout, stderr, wait_thread|
            stdin.close
            stdout_reader = Thread.new { stdout.read }
            stderr_reader = Thread.new { stderr.read }

            begin
              Timeout.timeout(timeout) { status = wait_thread.value }
            rescue Timeout::Error
              terminate(wait_thread)
              raise CommandTimeout
            ensure
              stdout_text = collect(stdout_reader, stdout)
              stderr_text = collect(stderr_reader, stderr)
            end
          end

          [stdout_text, stderr_text, status]
        end

        def result(stdout, stderr, status)
          Result.new(stdout:, stderr:, exitstatus: status.exitstatus, termsig: status.termsig)
        end

        def collect(reader, stream)
          return reader.value if reader.join(2)

          stream.close
          reader.kill
          reader.join
          ""
        end

        def terminate(wait_thread)
          Process.kill("TERM", -wait_thread.pid)
          Timeout.timeout(2) { wait_thread.value }
        rescue Errno::ESRCH
          nil
        rescue Timeout::Error
          Process.kill("KILL", -wait_thread.pid)
          wait_thread.value
        end
      end

      def initialize(
        models_dir:,
        timeout_per_file: 60,
        python_executable: "python3",
        command_runner: CommandRunner.new
      )
        @models_dir = Pathname(models_dir)
        @timeout_per_file = timeout_per_file
        @python_executable = python_executable.to_s
        @command_runner = command_runner
      end

      def preflight_environment!
        result = run_command(
          [python_executable, "-c", "import essentia.standard"],
          timeout: STARTUP_GRACE
        )
        raise_for_fatal_exit!(result) || true
      rescue CommandTimeout
        raise BackendError, "Essentia environment preflight timed out"
      end

      def preflight_plan!(plan)
        return true if plan.graphs.empty?

        result = run_command(
          [python_executable, SCRIPT_PATH.to_s, "--verify", "--models-dir", models_dir.to_s],
          timeout: command_timeout
        )
        raise_for_fatal_exit!(result)
        true
      rescue CommandTimeout
        raise BackendError, "Essentia plan preflight timed out"
      end

      def analyze(path, plan:)
        raise ArgumentError, "plan must be a MoodProbe::Plan" unless plan.is_a?(Plan)

        pathname = Pathname(path)
        result = run_command(
          [python_executable, SCRIPT_PATH.to_s, pathname.to_s, "--models-dir", models_dir.to_s],
          timeout: command_timeout
        )
        return process_error(result, pathname) if result.exitstatus.nil? && result.termsig

        raise_for_fatal_exit!(result)
        parse_result(result.stdout, pathname)
      rescue CommandTimeout
        TimeoutError.new("Essentia extraction timed out for #{pathname}")
      end

      private

      attr_reader :models_dir, :timeout_per_file, :python_executable, :command_runner

      def command_timeout
        STARTUP_GRACE + timeout_per_file
      end

      def run_command(command, timeout:)
        command_runner.call(command, timeout:)
      rescue CommandLaunchError => e
        raise ConfigurationError, "unable to launch Python executable #{python_executable}: #{e.message}"
      end

      def raise_for_fatal_exit!(result)
        return if result.exitstatus&.zero?

        message = result.stderr.to_s.strip
        if result.exitstatus.nil?
          signal = result.termsig ? " by signal #{result.termsig}" : ""
          raise BackendError, "Essentia backend terminated#{signal}"
        end
        message = "Essentia backend exited #{result.exitstatus}" if message.empty?
        error_class = result.exitstatus == 2 ? ConfigurationError : BackendError
        raise error_class, message
      end

      def process_error(result, pathname)
        BackendProcessError.new(
          "Essentia extraction terminated by signal #{result.termsig} for #{pathname}"
        )
      end

      def parse_result(output, requested_path)
        lines = output.lines.reject { |line| line.strip.empty? }
        raise BackendError, "Essentia backend returned no result for #{requested_path}" unless lines.one?

        payload = JSON.parse(lines.first)
        unless payload["path"] == requested_path.to_s
          raise BackendError, "Essentia backend returned a result for the wrong path"
        end
        return error_from_payload(payload["error"]) if payload["error"]
        raise BackendError, "Essentia backend omitted features for #{requested_path}" unless payload["features"]

        payload["features"]
      rescue JSON::ParserError => e
        raise BackendError, "Essentia backend returned invalid NDJSON: #{e.message}"
      end

      def error_from_payload(error)
        message = error["message"].to_s
        case error["type"]
        when "unreadable_audio"
          UnreadableAudioError.new(message)
        when "inference_error"
          InferenceError.new(message)
        when "malformed_output"
          MalformedOutputError.new(message)
        else
          raise BackendError, "Essentia backend returned unknown error type: #{error['type']}"
        end
      end
    end
  end
end
