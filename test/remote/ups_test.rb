require_relative '../test_helper'

class UPSTest < Test::Unit::TestCase

  def setup
    @packages = TestFixtures.packages
    @locations = TestFixtures.locations
    @carrier = UPS.new(fixtures(:ups).merge(:test => true))
  end

  def test_tracking
    assert_nothing_raised do
      response = @carrier.find_tracking_info('1Z12345E0291980793')
    end
  end

  def test_tracking_with_bad_number
    assert_raises ResponseError do
      response = @carrier.find_tracking_info('1Z12345E029198079')
    end
  end

  def test_tracking_with_another_number
    assert_nothing_raised do
      response = @carrier.find_tracking_info('1Z12345E6692804405')
    end
  end

  def test_us_to_uk
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
            @locations[:beverly_hills],
            @locations[:london],
            @packages.values_at(:big_half_pound),
            :test => true
      )
    end
  end

  def test_puerto_rico
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
            @locations[:beverly_hills],
            Location.new(:city => 'Ponce', :country => 'US', :state => 'PR', :zip => '00733-1283'),
            @packages.values_at(:big_half_pound),
            :test => true
      )
    end
  end

  def test_just_country_given
    response = @carrier.find_rates(
          @locations[:beverly_hills],
          Location.new(:country => 'CA'),
          Package.new(100, [5, 10, 20])
    )
    assert_not_equal [], response.rates
  end

  def test_ottawa_to_beverly_hills
    response = nil
    assert_nothing_raised do
      response = @carrier.find_rates(
            @locations[:ottawa],
            @locations[:beverly_hills],
            @packages.values_at(:book, :wii),
            :test => true
      )
    end

    assert response.success?, response.message
    assert_instance_of Hash, response.params
    assert_instance_of String, response.xml
    assert_instance_of Array, response.rates
    assert_not_equal [], response.rates

    rate = response.rates.first
    assert_equal 'UPS', rate.carrier
    assert_equal 'CAD', rate.currency
    assert_instance_of Fixnum, rate.total_price
    assert_instance_of Fixnum, rate.price
    assert_instance_of String, rate.service_name
    assert_instance_of String, rate.service_code
    assert_instance_of Array, rate.package_rates
    assert_equal @packages.values_at(:book, :wii), rate.packages

    package_rate = rate.package_rates.first
    assert_instance_of Hash, package_rate
    assert_instance_of Package, package_rate[:package]
    assert_nil package_rate[:rate]
  end

  def test_ottawa_to_us_fails_without_zip
    assert_raises ResponseError do
      @carrier.find_rates(
            @locations[:ottawa],
            Location.new(:country => 'US'),
            @packages.values_at(:book, :wii),
            :test => true
      )
    end
  end

  def test_ottawa_to_us_succeeds_with_only_zip
    assert_nothing_raised do
      @carrier.find_rates(
            @locations[:ottawa],
            Location.new(:country => 'US', :zip => 90210),
            @packages.values_at(:book, :wii),
            :test => true
      )
    end
  end

  def test_us_to_uk_with_different_pickup_types
    assert_nothing_raised do
      daily_response = @carrier.find_rates(
            @locations[:beverly_hills],
            @locations[:london],
            @packages.values_at(:book, :wii),
            :pickup_type => :daily_pickup,
            :test => true
      )
      one_time_response = @carrier.find_rates(
            @locations[:beverly_hills],
            @locations[:london],
            @packages.values_at(:book, :wii),
            :pickup_type => :one_time_pickup,
            :test => true
      )
      assert_not_equal daily_response.rates.map(&:price), one_time_response.rates.map(&:price)
    end
  end

  def test_bare_packages
    response = nil
    p = Package.new(0, 0)
    assert_nothing_raised do
      response = @carrier.find_rates(
            @locations[:beverly_hills], # imperial (U.S. origin)
            @locations[:ottawa],
            p,
            :test => true
      )
    end
    assert response.success?, response.message
    assert_nothing_raised do
      response = @carrier.find_rates(
            @locations[:ottawa],
            @locations[:beverly_hills], # metric
            p,
            :test => true
      )
    end
    assert response.success?, response.message
  end

  def test_different_rates_based_on_address_type
    responses = {}
    locations = [
          :fake_home_as_residential, :fake_home_as_commercial,
          :fake_google_as_residential, :fake_google_as_commercial
    ]

    locations.each do |location|
      responses[location] = @carrier.find_rates(
            @locations[:beverly_hills],
            @locations[location],
            @packages.values_at(:chocolate_stuff)
      )
    end

    prices_of = lambda { |sym| responses[sym].rates.map(&:price) }

    assert_not_equal prices_of.call(:fake_home_as_residential), prices_of.call(:fake_home_as_commercial)
    assert_not_equal prices_of.call(:fake_google_as_commercial), prices_of.call(:fake_google_as_residential)
  end

  def test_confirmation_with_dry_ice
    account_number = fixtures(:ups)[:account]

    confirmation_options = TestFixtures.confirmation_request_options account_number, [@packages[:perishable_wii]]

    assert_nothing_raised do
      @confirmation_response = @carrier.get_confirmation_response(confirmation_options)
    end

    assert_equal true, @confirmation_response.success?
  end

  def test_confirmation
    account_number = fixtures(:ups)[:account]

    confirmation_options = TestFixtures.confirmation_request_options account_number

    assert_nothing_raised do
      @confirmation_response = @carrier.get_confirmation_response(confirmation_options)
    end

    assert_equal true, @confirmation_response.success?
  end

  def test_acceptance
    account_number = fixtures(:ups)[:account]
    packages = [@packages[:wii], @packages[:chocolate_stuff]]

    confirmation_options = TestFixtures.confirmation_request_options account_number, packages

    confirmation_response = @carrier.get_confirmation_response(confirmation_options)
    acceptance_options = TestFixtures.acceptance_request_options.update({shipment_digest: confirmation_response.shipment_digest})

    assert_nothing_raised do
      @acceptance_response = @carrier.get_acceptance_response(acceptance_options)
    end

    assert_equal true, @acceptance_response.success?
    assert_nil @acceptance_response.high_value_report
  end

  def test_acceptance_with_hvr
    account_number = fixtures(:ups)[:account]
    packages = [@packages[:expensive_wii]]

    confirmation_options = TestFixtures.confirmation_request_options account_number, packages
    confirmation_response = @carrier.get_confirmation_response(confirmation_options)
    acceptance_options = TestFixtures.acceptance_request_options.update({shipment_digest: confirmation_response.shipment_digest})

    assert_nothing_raised do
      @acceptance_response = @carrier.get_acceptance_response(acceptance_options)
    end
    assert_equal true, @acceptance_response.success?
    assert_not_nil @acceptance_response.high_value_report
  end

  def test_void
    void_request_options = TestFixtures.void_request_options[:condensed]

    void_response = @carrier.get_unparsed_void_response(void_request_options)

    xml = REXML::Document.new(void_response)
    assert_equal '1', xml.get_text('/*/Response/ResponseStatusCode').to_s
  end

  def test_address_validation
    response = @carrier.get_address_validation_response TestFixtures.address_validation_request_options

    assert_equal true, response.success?
    assert_equal :valid, response.indicator
  end

  def test_quantum_view
    assert_nothing_raised do
      @quantum_view_response = @carrier.get_quantum_view_response
    end

    assert_equal true, @quantum_view_response.success?
  end
end
