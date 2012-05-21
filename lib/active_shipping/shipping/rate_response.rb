module ActiveMerchant #:nodoc:
  module Shipping
    
    class RateResponse < Response
      
      attr_reader :rates
      
      def initialize(success, message, params = {}, options = {})
        @rates = Array(options[:estimates] || options[:rates] || options[:rate_estimates])
        puts  unless success

        unless success
          msg = "Error in getting rates response [XML RESPONSE IS]: #{options[:xml]}"
          if defined? Rails.logger
            Rails.logger.error msg
          else
            p msg
          end
        end

        super
      end
      
      alias_method :estimates, :rates
      alias_method :rate_estimates, :rates
      
    end
    
  end
end