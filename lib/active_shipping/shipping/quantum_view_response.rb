module ActiveMerchant #:nodoc:
  module Shipping

    class QuantumViewResponse < Response
      attr_accessor :shipped_info
      attr_reader :bookmark

      def initialize(success, message, params = {}, options = {})
        @shipped_info = options[:shipped_info]
        @bookmark = options[:bookmark]
        super
      end
    end
  end
end