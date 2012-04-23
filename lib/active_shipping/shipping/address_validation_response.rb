module ActiveMerchant #:nodoc:
  module Shipping

    class AddressValidationResponse < Response
      attr_reader :indicator

      def initialize(success, message, params = {}, options = {})
        @indicator = options[:indicator]
        super
      end
    end
  end
end