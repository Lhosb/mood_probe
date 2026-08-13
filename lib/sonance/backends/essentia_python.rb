require "json"
require "open3"
require "pathname"
require "tempfile"
require "timeout"

module Sonance
  module Backends
    # rubocop:disable Metrics/ClassLength
    class EssentiaPython
      STARTUP_GRACE = 10
      PLAN_ARGUMENT_LIMIT = 64 * 1024
      SCRIPT_PATH = Pathname(__dir__).join("../../../python/sonance_extract.py").expand_path

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
        result = with_plan_arguments(plan) do |plan_arguments|
          run_command(
            [
              python_executable,
              SCRIPT_PATH.to_s,
              "--verify",
              "--models-dir",
              models_dir.to_s,
              *plan_arguments
            ],
            timeout: command_timeout
          )
        end
        raise_for_fatal_exit!(result)
        true
      rescue CommandTimeout
        raise BackendError, "Essentia plan preflight timed out"
      end

      def analyze(path, plan:)
        analyze_all([path], plan:).first
      end

      def analyze_all(paths, plan:)
        raise ArgumentError, "plan must be a Sonance::Plan" unless plan.is_a?(Plan)

        pathnames = paths.map { |path| Pathname(path) }
        result = run_analysis(pathnames, plan)
        return process_errors(result, pathnames) if result.exitstatus.nil? && result.termsig

        raise_for_fatal_exit!(result)
        parse_results(result.stdout, pathnames)
      rescue CommandTimeout
        pathnames.map { |pathname| TimeoutError.new("Essentia extraction timed out for #{pathname}") }
      end

      private

      attr_reader :models_dir, :timeout_per_file, :python_executable, :command_runner

      def command_timeout
        STARTUP_GRACE + timeout_per_file
      end

      def batch_command_timeout(path_count)
        STARTUP_GRACE + (timeout_per_file * [path_count, 1].max)
      end

      def run_analysis(pathnames, plan)
        with_plan_arguments(plan) do |plan_arguments|
          run_command(
            [
              python_executable,
              SCRIPT_PATH.to_s,
              *pathnames.map(&:to_s),
              "--models-dir",
              models_dir.to_s,
              *plan_arguments
            ],
            timeout: batch_command_timeout(pathnames.length)
          )
        end
      end

      def with_plan_arguments(plan)
        payload = JSON.generate(plan.to_h)
        return yield(["--plan-json", payload]) if payload.bytesize <= PLAN_ARGUMENT_LIMIT

        # This is a system-tmpdir subprocess handoff, not a durable models_dir artifact.
        Tempfile.create(["sonance-plan", ".json"]) do |file|
          file.write(payload)
          file.flush
          yield(["--plan-file", file.path])
        end
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

      def process_errors(result, pathnames)
        pathnames.map { |pathname| process_error(result, pathname) }
      end

      def parse_results(output, requested_paths)
        lines = output.lines.reject { |line| line.strip.empty? }
        validate_result_count!(lines, requested_paths)
        lines.zip(requested_paths).map { |line, path| parse_line(line, path) }
      rescue JSON::ParserError => e
        raise BackendError, "Essentia backend returned invalid NDJSON: #{e.message}"
      end

      def validate_result_count!(lines, requested_paths)
        return if lines.length == requested_paths.length

        raise BackendError,
              "Essentia backend returned #{lines.length} results for #{requested_paths.length} paths"
      end

      def parse_line(line, requested_path)
        payload = JSON.parse(line)
        unless payload["path"] == requested_path.to_s
          raise BackendError, "Essentia backend returned a result for the wrong path"
        end

        return error_from_payload(payload["error"]) if payload["error"]
        return payload["features"] if payload["features"]

        raise BackendError, "Essentia backend omitted features for #{requested_path}"
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
      # rubocop:enable Metrics/ClassLength
    end
  end
end
