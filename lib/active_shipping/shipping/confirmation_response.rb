module ActiveMerchant #:nodoc:
  module Shipping

    class ConfirmationResponse < Response
      attr_reader :total_cost, :shipment_identification_number, :shipment_digest, :xml_response

      def initialize(success, message, params = {}, options = {})
        @total_cost = options[:total_cost]
        @shipment_identification_number = options[:shipment_identification_number]
        @shipment_digest = options[:shipment_digest]
        @xml_response = options[:xml_response]

        unless success
          msg = "Error in getting confirmation response [XML RESPONSE IS]: #{@xml_response}"
          if defined? Rails.logger
            Rails.logger.error msg
          else
            p msg
          end
        end

        super
      end

    end
  end
end