require_relative '../test_helper'

class PeriShipTest < Test::Unit::TestCase

  def setup
    @packages = TestFixtures.packages
    @locations = TestFixtures.locations
    @carrier = PeriShip.new(fixtures(:periship).merge(:test => true))
  end

  def test_rates
    assert_nothing_raised do
      residential_response = @carrier.find_rates(
          @locations[:beverly_hills],
          @locations[:real_google_as_residential],
          @packages.values_at(:expensive_wii, :wii)
      )
    end
  end
end
