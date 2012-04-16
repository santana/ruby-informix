testdir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift testdir

require 'testcase'

class IfxTestSelect < Informix::TestCase
  def setup
    connect_string, username, password = ARGV[0..2]
    super connect_string, username, password
    drop_test_table
    create_test_table
    populate_test_table
  end

  def test_select
    rows = nil
    assert_nothing_raised(Informix::Error, "Selecting records") do
      rows = db.cursor('select * from test') { |c| c.open; c.fetch_all }
    end
    
    assert_equal(2, rows.size, "# of records retrieved")
    
    exp_rows = @rows

    2.times do |i|
      assert_equal(exp_rows[i].shift, rows[i].shift, "serial")
      assert_equal(exp_rows[i].shift, rows[i].shift, "char")
      assert_equal(exp_rows[i].shift, rows[i].shift, "varchar")
      assert_equal(exp_rows[i].shift, rows[i].shift, "smallint")
      assert_equal(exp_rows[i].shift, rows[i].shift, "integer")
      
      assert_in_delta(exp_rows[i].shift, rows[i].shift, 1e-6, "smallfloat")
      assert_in_delta(exp_rows[i].shift, rows[i].shift, 1e-14, "float")

      obj = rows[i].shift
      obj = obj.strftime("%m/%d/%Y") if obj.respond_to? :strftime
      exp = exp_rows[i].shift
      exp = exp.strftime("%m/%d/%Y") if exp.respond_to? :strftime

      assert_equal(exp, obj, "date")
      
      obj = rows[i].shift
      obj = obj.strftime("%Y-%m-%d %H:%M:%S.000") if obj.respond_to? :strftime
      exp = exp_rows[i].shift
      exp = exp.strftime("%Y-%m-%d %H:%M:%S.000") if exp.respond_to? :strftime

      assert_equal(exp, obj, "datetime")
      
      assert_equal(exp_rows[i].shift, rows[i].shift, "interval year to month")
      assert_equal(exp_rows[i].shift, rows[i].shift, "interval day to second")

      assert_equal(exp_rows[i].shift, rows[i].shift, "decimal")

      obj = rows[i].shift
      exp = exp_rows[i].shift

      if obj.class == StringIO
        obj.rewind 
        obj = obj.read # Convert to string
      end

      if exp.class == StringIO
        exp.rewind 
        exp = exp.read # Convert to string
      end

     assert_equal(exp, obj, "text")

      if @supported["boolean"]
        assert_equal(exp_rows[i].shift, rows[i].shift ? 't': 'f', "boolean")
      end
      
      if @supported["int8"]
        assert_equal(exp_rows[i].shift, rows[i].shift, "int8")
      end

    end
  end
end
