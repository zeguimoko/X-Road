java_import Java::ee.ria.xroad.commonui.SignerProxy

# Checks status of central components
class SystemStatusController < ApplicationController

  CONF_GENERATION_TIMEOUT_SECS = 300

  skip_before_filter :check_conf, :only => [:check_status]

  before_filter :verify_get, :only => [:check_status]

  def index
  end

  def check_status
    alerts = []

    if initialized?
      check_global_conf_generation_status(alerts)

      begin
        check_configuration_signing_keys(
          ConfigurationSource::SOURCE_TYPE_INTERNAL, alerts)

        if SystemProperties::getCenterTrustedAnchorsAllowed
          check_configuration_signing_keys(
            ConfigurationSource::SOURCE_TYPE_EXTERNAL, alerts)
        end
      rescue
        alerts << t("status.signing_key.signer_error", :message => $!.message)
      end
    end

    render :json => {
      :alerts => alerts
    }
  end

  private

  def check_global_conf_generation_status(alerts)
    generation_status = GlobalConfGenerationStatus.get

    logger.info("Global configuration generation status from file: " \
        "'#{generation_status}'")

    last_attempt_time = generation_status[:time]

    if generation_status[:success] == true
      alerts << t("status.global_conf_gen.out_of_date", {
        :time => format_time(last_attempt_time)
      }) if conf_expired?(last_attempt_time)

      return
    end

    if generation_status[:no_status_file] == true
      alerts << t("status.global_conf_gen.no_status_file")
    else
      alerts << t("status.global_conf_gen.failure", {
        :time => format_time(last_attempt_time)
      })
    end
  end

  def check_configuration_signing_keys(source_type, alerts)
    signing_key = ConfigurationSource.get_source_by_type(source_type).active_key

    unless signing_key
      alerts << t("status.signing_key.#{source_type}.missing")
      return
    end

    SignerProxy::getTokens.each do |token|
      token.key_info.each do |key|
        next unless signing_key.key_identifier == key.id

        signing_key_found = true

        if !token.active
          alerts << t("status.signing_key.#{source_type}.token_not_active")
        elsif !key.available
          alerts << t("status.signing_key.#{source_type}.key_not_available")
        end

        return
      end
    end

    alerts << t("status.signing_key.#{source_type}.token_not_found")
  end

  def conf_expired?(generation_time)
    generation_time < Time.now() - SystemParameter.conf_expire_interval_seconds
  end

end