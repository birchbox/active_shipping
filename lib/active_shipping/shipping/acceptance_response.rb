module ActiveMerchant #:nodoc:
  module Shipping

    class AcceptanceResponse < Response
      attr_reader :total_cost, :shipment_identification_number, :packages, :high_value_report, :xml_response

      def initialize(success, message, params = {}, options = {})
        @total_cost = options[:total_cost]
        @shipment_identification_number = options[:shipment_identification_number]
        @packages = options[:packages]
        @high_value_report = (options[:high_value_report].empty?)? nil : options[:high_value_report]
        @xml_response = options[:xml_response]
        super
      end

      def save_files_for_package_with_tracking_number(tracking_number, file_path_basename)
        package = @packages.select { |p| p[:tracking_number] == tracking_number }.first
        if package
          File.open("#{file_path_basename}.gif", 'wb') do |file|
            file.write(package[:image_data])
          end
          File.open("#{file_path_basename}.html", 'wb') do |file|
            file.write(package[:label_html])
          end
        else
          raise 'Invalid Tracking Number'
        end
      end

      def save_high_value_report_for_shipment file_path
        if @high_value_report
          File.open(file_path, 'wb') do |file|
            file.write(@high_value_report)
          end
        else
          raise 'Package did not generate a high value report'
        end
      end
    end
  end
end