require_relative '../../test_helper'

class PeriShipTest < Test::Unit::TestCase

  def setup
    @packages  = TestFixtures.packages
    @locations = TestFixtures.locations
    @carrier = PeriShip.new(fixtures(:periship).merge(:test => true))
  end

  def test_initialize_options_requirements
    assert_raises(ArgumentError) { PeriShip.new }
    assert_raises(ArgumentError) { PeriShip.new(login: 'blah', password: 'bloo') }
    assert_raises(ArgumentError) { PeriShip.new(login: 'blah', key: 'kee') }
    assert_raises(ArgumentError) { PeriShip.new(password: 'bloo', key: 'kee') }
    assert_nothing_raised { PeriShip.new(login: 'blah', password: 'bloo', key: 'kee') }
  end

end
