module ActiveMerchant #:nodoc:
  module Shipping

    class VoidResponse < Response
      attr_accessor :voided

      def initialize(success, message, params = {}, options = {})
        super success, message, params, options

        self.voided = options[:voided]
      end

      def voided_shipment?
        self.voided
      end
    end
  end
end