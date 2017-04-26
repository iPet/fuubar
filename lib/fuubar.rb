# frozen_string_literal: true
require 'rspec/core'
require 'rspec/core/formatters/base_text_formatter'
require 'ruby-progressbar'
require 'fuubar/output'
require 'redis'

RSpec.configuration.add_setting :fuubar_progress_bar_options, :default => {}

class Fuubar < RSpec::Core::Formatters::BaseTextFormatter
  DEFAULT_PROGRESS_BAR_OPTIONS = { :format => ' %c/%C |%w>%i| %e ' }.freeze
  REDIS = ::Redis.new

  RSpec::Core::Formatters.register self,  :start,
                                   :message,
                                   :example_passed,
                                   :example_pending,
                                   :example_failed,
                                   :dump_failures

  attr_accessor :progress

  def initialize(*args)
    super

    self.progress = ProgressBar.create(
                      DEFAULT_PROGRESS_BAR_OPTIONS.
                        merge(:throttle_rate => continuous_integration? ? 1.0 : nil).
                        merge(:total     => 0,
                              :output    => output,
                              :autostart => false)
    )
  end

  def start(notification)
    progress_bar_options = DEFAULT_PROGRESS_BAR_OPTIONS.
                           merge(:throttle_rate => continuous_integration? ? 1.0 : nil).
                           merge(configuration.fuubar_progress_bar_options).
                           merge(:total     => notification.count,
                                 :output    => output,
                                 :autostart => false)

    self.progress      = ProgressBar.create(progress_bar_options)
    REDIS.set("passed_coun", 0)
    REDIS.set("pending_count", 0)
    REDIS.set("failed_count", 0)

    super

    with_current_color { progress.start }
  end

  def example_passed(_notification)
    REDIS.incr("passed_count")

    increment
  end

  def example_pending(_notification)
    REDIS.incr("pending_count")

    increment
  end

  def example_failed(notification)
    REDIS.incr("failed_count")

    progress.clear

    output.puts notification.fully_formatted(REDIS.get("failed_count"))
    output.puts

    increment
  end

  def message(notification)
    if progress.respond_to? :log
      progress.log(notification.message)
    else
      super
    end
  end

  def dump_failures(_notification)
    #
    # We output each failure as it happens so we don't need to output them en
    # masse at the end of the run.
    #
  end

  def output
    @fuubar_output ||= Fuubar::Output.new(super, configuration.tty?)
  end

  private

  def increment
    with_current_color { progress.increment }
  end

  def with_current_color
    output.print "\e[#{color_code_for(current_color)}m" if color_enabled?
    yield
    output.print "\e[0m"                                if color_enabled?
  end

  def color_enabled?
    configuration.color_enabled? && !continuous_integration?
  end

  def current_color
    if REDIS.get("failed_count").to_i > 0
      configuration.failure_color
    elsif REDIS.get("pending_count").to_i > 0
      configuration.pending_color
    else
      configuration.success_color
    end
  end

  def color_code_for(*args)
    RSpec::Core::Formatters::ConsoleCodes.console_code_for(*args)
  end

  def configuration
    RSpec.configuration
  end

  def continuous_integration?
    @continuous_integration ||= \
      ![nil, '', 'false'].include?(ENV['CONTINUOUS_INTEGRATION'])
  end
end
