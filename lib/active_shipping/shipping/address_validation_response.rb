module ActiveMerchant #:nodoc:
  module Shipping

    class AddressValidationResponse < Response
      def initialize(success, message, params = {}, options = {})
        @xml_response = options[:xml_response]
        super
      end
    end
  end
end