module ActiveMerchant #:nodoc:
  module Shipping

    class ConfirmationResponse < Response
      attr_reader :total_cost, :shipment_identification_number, :shipment_digest

      def initialize(success, message, params = {}, options = {})
        @total_cost = options[:total_cost]
        @shipment_identification_number = options[:shipment_identification_number]
        @shipment_digest = options[:shipment_digest]
        super
      end

    end
  end
end