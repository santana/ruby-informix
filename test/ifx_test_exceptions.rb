testdir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift testdir

require 'testcase'

class IfxTestExceptions < Informix::TestCase
  def info_params
    [ 
      [ -100, "IX111", "IX", "000", "Some message", "server", "conn" ],
      [ -200, "IX111", "IX", "000", "Some message", "server", "conn" ],
      [ -300, "IX111", "IX", "000", "Some message", "server", "conn" ]
    ]
  end

  # Don't need an Informix database for these tests
  def setup
    @info_arr = info_params.map { |arr| Informix::ExcInfo.new(*arr) }
    @test_exc = Informix::Error.new @info_arr
  end

  # Also tests Informix::Error#each via each_with_index
  def test_add_info
    params = self.info_params
    exc = Informix::Error.new
    params.each { |arr| exc.add_info(*arr) }
    exc.each_with_index { |info, i| assert_equal params[i], info.to_a }
  end

  def test_each_for_empty_exception
    exc = Informix::Error.new
    assert_nothing_raised { exc.each { |x| } }
  end
  
  def test_size
    assert_equal info_params.size, @test_exc.size
  end

  def test_length
    assert_equal info_params.length, @test_exc.length
  end

  def test_initialize_type_error
    assert_raise(TypeError) { Informix::Error.new [1, 2, 3] }
    assert_raise(TypeError) { Informix::Error.new 0 }
  end

  def test_initialize_with_string
    err = nil
    expected_msg = "This is a message"
    assert_nothing_raised { err = Informix::Error.new expected_msg }
    assert_equal expected_msg, err.message
  end

  def test_to_s
    assert_nothing_raised { @test_exc.to_s }
  end

  def test_at
    @test_exc.size.times { |i| assert_equal @info_arr[i], @test_exc[i] }
  end
  
  def test_sqlcode
    assert_equal(-100, @test_exc.sql_code)
    assert_equal 0, Informix::Error.new.sql_code
  end
  
end

