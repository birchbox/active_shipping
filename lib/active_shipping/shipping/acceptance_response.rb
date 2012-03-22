module ActiveMerchant #:nodoc:
  module Shipping

    class AcceptanceResponse < Response
      attr_reader :total_cost, :shipment_identification_number, :packages

      def initialize(success, message, params = {}, options = {})
        @total_cost = options[:total_cost]
        @shipment_identification_number = options[:shipment_identification_number]
        @packages = options[:packages]
        super
      end

      def save_image_for_package_with_tracking_number(tracking_number, file_path)
        package = @packages.select { |p| p[:tracking_number] == tracking_number }.first
        if package
          File.open(file_path, 'wb') do |file|
            file.write(package[:image_data])
          end
        else
          raise 'Invalid Tracking Number'
        end
      end

    end
  end
end