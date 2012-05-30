module ActiveMerchant
  module Shipping
    class PeriShip < Carrier
      self.retry_safe = true

      cattr_reader :name
      @@name = "PeriShip"

      URL = 'http://www.periship.com/invoicing/controller/PeriShip.php'

      RESOURCES = {
          :rates => 'shipment'
      }

      US_TERRITORIES_TREATED_AS_COUNTRIES = ["AS", "FM", "GU", "MH", "MP", "PW", "PR", "VI"]

      DEFAULT_SERVICES = {
          "1" => FedEx::ServiceTypes["PRIORITY_OVERNIGHT"],
          "3" => FedEx::ServiceTypes["FEDEX_2_DAY"],
          "5" => FedEx::ServiceTypes["STANDARD_OVERNIGHT"],
          "20" => FedEx::ServiceTypes["FEDEX_EXPRESS_SAVER"],
          "90" => FedEx::ServiceTypes["GROUND_HOME_DELIVERY"],
          "92" => FedEx::ServiceTypes["FEDEX_GROUND"]
      }

      RECIPIENT_TYPES = HashWithIndifferentAccess.new({
                                                          residential_address: "R",
                                                          commercial_address: "C"
                                                      })

      SIGNATURE_TYPES = HashWithIndifferentAccess.new({
                                                          direct_signature_required: "D",
                                                          adult_signature_required: "A"
                                                      })

      RETURN_TYPES = HashWithIndifferentAccess.new({
                                                       summary: "S",
                                                       detailed: "D"
                                                   })

      def requirements
        [:key, :login, :password]
      end

      def find_rates(origin, destination, packages, options = {})
        origin, destination = upsified_location(origin), upsified_location(destination)
        options = @options.merge(options)
        packages = Array(packages)

        package_nodes = create_package_nodes(packages, options)
        rate_template = build_rate_request_template(origin, destination, packages, options)

        x = Time.now
        response = nil
        rate_estimates = nil

        package_nodes.each do |package|
          rate_request = build_rate_request(rate_template, package, options)
          y = Time.now
          new_response = commit(:rates, save_request(rate_request))
          puts 'Individual Time: ', Time.now - y

          #TODO: refactor to merge rates in parse_rate_response
          new_response = parse_rate_response(origin, destination, packages, new_response, options)

          rate_estimates = merge_rate_estimates(rate_estimates, new_response.rates)
          #TODO: create correct response
          response = new_response
        end

        puts 'Total Time: ', Time.now - x
        response
      end

      protected

      def upsified_location(location)
        if location.country_code == 'US' && US_TERRITORIES_TREATED_AS_COUNTRIES.include?(location.state)
          atts = {:country => location.state}
          [:zip, :city, :address1, :address2, :address3, :phone, :fax, :address_type].each do |att|
            atts[att] = location.send(att)
          end
          Location.new(atts)
        else
          location
        end
      end

      def build_rate_request_template(origin, destination, packages, options={})
        xml_request = XmlNode.new('PeriShipRateRequest') do |root_node|

          root_node << XmlNode.new('RequestHeader') do |access_request|
            access_request << XmlNode.new('ShipperID', options[:login])
            access_request << XmlNode.new('ShipperPassword', options[:password])
            access_request << XmlNode.new('ShipperZipCode', origin.postal_code)
          end

          root_node << XmlNode.new('RecipientInfo') do |recipient_info|
            #recipient_info << XmlNode.new("RecipientName", options[:attention_name])
            recipient_info << XmlNode.new("RecipientStreet", destination.address1)
            recipient_info << XmlNode.new("RecipientCity", destination.city)
            recipient_info << XmlNode.new("RecipientState", destination.province)
            recipient_info << XmlNode.new("RecipientZip", destination.postal_code)
          end

          root_node << XmlNode.new('PackageInfo')

          root_node << XmlNode.new('ReturnType') do |return_type|
            return_type << XmlNode.new("FeeDetail", RETURN_TYPES[:summary])
          end

        end

        xml_request
      end

      def build_rate_request(request_template, package, options={})
        xml_request = "<#{request_template.element.name}>"

        XmlNode::List.new(request_template).each do |element|
          xml_request << ((element.name == 'PackageInfo') ? package.to_s : element.to_s)
        end
        xml_request << "</#{request_template.element.name}>"

        xml_request
      end

      def create_package_nodes(packages, options={})
        xml_request = Array.new

        packages.each do |package|
          package_node = XmlNode.new('PackageInfo') do |package_info|
            package_info << XmlNode.new("Weight", package.pounds)
            package_info << XmlNode.new("Service", options[:service]) if options[:service]
            package_info << XmlNode.new("RecipientType", "R") # destination.commercial? ? RECIPIENT_TYPES[:commercial_address] : RECIPIENT_TYPES[:residential_address])
            package_info << XmlNode.new("SignatureType", options[:signatureType]) if options[:signatureType]
            if package.value
              value = (BigDecimal.new(package.value.to_s) / 100).round(2).to_s('F')
              package_info << XmlNode.new('DeclaredValue', value)
            end
            package_info << XmlNode.new("SaturdayDelivery", options[:signatureType]) if options[:signatureType]
            package_info << XmlNode.new("ShipDate", options[:shipDate]) if options[:shipDate]
            package_info << XmlNode.new("DryIce", "Y") if package.dry_ice_weight

            xml_request << package_info
          end
        end

        xml_request
      end

      def parse_rate_response(origin, destination, packages, response, options={})
        rate_estimates = []

        xml = REXML::Document.new(response)

        success = response_success?(xml)
        message = response_message(xml)

        if success
          rate_estimates = []

          xml.elements.each('/*/ServiceItem') do |service_item|
            service_code = service_item.get_text('ServiceCode').to_s
            days_to_delivery = service_item.get_text('daysInTransit').to_s.to_i
            delivery_date = (days_to_delivery.between?(0, 99)) ? days_to_delivery.days.from_now.strftime("%Y-%m-%d") : nil

            rate_estimates << RateEstimate.new(origin, destination, @@name,
                                               :service_name => DEFAULT_SERVICES[service_code],
                                               :total_price => service_item.get_text('TotalFee').to_s.to_f,
                                               :currency => 'USD',
                                               :service_code => service_code,
                                               :packages => packages,
                                               :delivery_range => [delivery_date])

          end
        end

        RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request)
      end

      def merge_rate_estimates(rates, new_rate_estimates)
        puts 'rates_in:', rates

        return new_rate_estimates if rates.nil?

        cnt = 0
        new_rate_estimates.each do |new_rate|
          service_name = new_rate.service_name[:service_name]
          service_rate = new_rate.service_name[:total_price]
          puts 'new_service_name_in:', service_name, 'service_name_in', rates[cnt].service_name[:service_name]
          puts 'new_service_total_in:', service_rate, 'service_total_in', rates[cnt].service_name[:total_price]
          rates[cnt].service_name[:total_price] += new_rate.service_name[:total_price]
          puts 'total_price_out:', rates[cnt].service_name[:total_price]
          #cnt += 1
        end

        puts 'rates_out:', rates

      end

      def response_success?(xml)
        xml.get_text('/*/ResponseHeader/ErrorCount').to_s == '0'
      end

      def response_message(xml)
        xml.get_text('/*/Errors/ErrorItem/ErrorDescription').to_s
      end

      def commit(action, request)
        ssl_post(URL, "#{RESOURCES[action]}=#{request}")
      end

    end
  end
end
