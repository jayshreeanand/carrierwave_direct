require "carrierwave_direct/policies/base"

module CarrierWaveDirect
  module Policies
    class Aws4HmacSha256 < Base

      def date
        @date ||= Time.now.utc.strftime("%Y%m%d")
      end

      def timestamp
        @timestamp ||= Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      end

      def generate(options, &block)

        return @policy if @policy.present?
        conditions = []

        conditions << ["starts-with", "$utf8", ""] if options[:enforce_utf8]
        conditions << ["starts-with", "$key", uploader.key.sub(/#{Regexp.escape(CarrierWaveDirect::Uploader::FILENAME_WILDCARD)}\z/, "")]
        conditions << {'X-Amz-Algorithm' => algorithm}
        conditions << {'X-Amz-Credential' => credential}
        conditions << {'X-Amz-Date' => date }
        conditions << ["starts-with", "$Content-Type", ""] if uploader.will_include_content_type
        conditions << {"bucket" => uploader.fog_directory}
        conditions << {"acl" => uploader.acl}

        if uploader.use_action_status
          conditions << {"success_action_status" => uploader.success_action_status}
        else
          conditions << {"success_action_redirect" => uploader.success_action_redirect}
        end

        conditions << ["content-length-range", options[:min_file_size], options[:max_file_size]]

        yield conditions if block_given?

        @policy = Base64.encode64(
          {
            'expiration' => (Time.now + options[:expiration]).utc.iso8601,
            'conditions' => conditions
          }.to_json
        ).gsub("\n","")
      end

      def credential
        "#{uploader.aws_access_key_id}/#{date}/#{uploader.region}/s3/aws4_request"
      end

      def algorithm
        'AWS4-HMAC-SHA256'
      end

      def clear!
        super
        @date = nil
        @timestamp = nil
      end

      def signature
        OpenSSL::HMAC.hexdigest(
          'sha256',
          signing_key,
          policy
        )
      end

      def signing_key(options = {})
        #AWS Signature Version 4
        kDate    = OpenSSL::HMAC.digest('sha256', "AWS4" + uploader.aws_secret_access_key, date)
        kRegion  = OpenSSL::HMAC.digest('sha256', kDate, uploader.region)
        kService = OpenSSL::HMAC.digest('sha256', kRegion, 's3')
        kSigning = OpenSSL::HMAC.digest('sha256', kService, "aws4_request")

        kSigning
      end
    end
  end
end
