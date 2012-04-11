testdir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift testdir
$LOAD_PATH.unshift File.expand_path(File.join(testdir, "..", "lib"))
$LOAD_PATH.unshift File.expand_path(File.join(testdir, "..", "ext"))

gem 'test-unit'
require 'test/unit'
require 'informix'
require 'date'
require 'stringio'

module Informix
  class TestCase < Test::Unit::TestCase
    NOW = Time.now.utc
    TODAY = Date.today
    MIN_INT64 = -9_223_372_036_854_775_807
    MAX_INT64= 9_223_372_036_854_775_807
    MAX_INT32 = 2_147_483_647
    MIN_INT32 = -2_147_483_647
    MIN_INT16 = -32767
    MAX_INT16 = 32767
    E = 2.71828183
    PI = 3.1415926535897932385
    DATE = '04/07/2006'
    DATE_TIME = '2006-04-07 01:40:55.000'
    BIGDECIMAL1 = BigDecimal.new('12456.78')
    BIGDECIMAL2 = BigDecimal.new('90123.45')
    INTERVALYM1 = -Informix::Interval.year_to_month(999999999, 11)
    INTERVALDS1 = -Informix::Interval.day_to_second(999999999, 23, 59,
                                                    Rational(5999999, 100000))
    INTERVALYM2 = Informix::Interval.year_to_month(999999999, 11)
    INTERVALDS2 = Informix::Interval.day_to_second(999999999, 23, 59,
                                                   Rational(5999999, 100000))
    TEXT = StringIO.new(<<-end_text)
      This is a TEXT field. You can
      write them using IO/IO-like objects
      and read them into Strings.
    end_text

    TEST_TABLE_NAME = "test"

    attr_reader :db

    def quote_strings(arr)
      arr.map { |v| if v.nil? then "NULL" else "\"#{v.to_s}\"" end }
    end

    def supported_data_type?(db, data_type)
      begin
        is_supported = true
        db.execute("create temp table temp_#{TEST_TABLE_NAME}(test_column #{data_type})")
      rescue Informix::Error => exc
        raise unless exc[0].sql_code == -201 # Syntax error
        is_supported = false
      ensure
        drop_table("temp_#{TEST_TABLE_NAME}") rescue nil
      end
      is_supported
    end

    def create_test_table
      columns = [
        ['id', 'serial', 'not null primary key'],
        ['char', 'char', '(30)'],
        ['varchar', 'varchar', '(30)'],
        ['smallint', 'smallint', '' ],
        ['integer', 'integer', '' ],
        ['smallfloat', 'smallfloat', '' ],
        ['float', 'float', '' ],
        ['date', 'date', '' ],
        ['datetime', 'datetime', 'year to fraction(5)' ],
        ['intervalym', 'interval', 'year(9) to month' ],
        ['intervalds', 'interval', 'day(9) to fraction(5)' ],
        ['decimal', 'decimal', '(9, 2)' ],
        ['text', 'text', '' ]
      ]

      if supported_data_type?(db, "boolean")
        columns << ['boolean', 'boolean', '' ]
      end

      if supported_data_type?(db, "int8")
        columns << ['int8', 'int8', '' ]
      end

      col_list = columns.map { |arr| arr.join(' ') }
      sql = "create temp table #{TEST_TABLE_NAME} (#{col_list.join(",")})"
      db.execute sql
    end

    def drop_test_table
      drop_table TEST_TABLE_NAME
    end

    def rewind_data
      @rows.each { |arr| arr.each { |elem| elem.rewind if elem.respond_to?(:rewind) }}
      TEXT.rewind
    end

    def populate_test_table
      sql = "insert into test values(#{quote_strings(@rows[0]).join(',')})"

      assert_nothing_raised(Informix::Error, "Inserting record with db.execute, sql = [#{sql}]") do
        db.execute sql
      end

      sql = "insert into test values(#{"?," * (@rows[1].size - 1)}#{"?"})"

      assert_nothing_raised(Informix::Error, "Inserting record with stmt.execute, sql = [#{sql}]") do
        db.prepare(sql) {|stmt| stmt.execute(*@rows[1]) }
      end
      ensure
        rewind_data
    end

    def drop_table(name)
      self.db.execute "drop table #{name}"
    rescue Informix::Error => exc
      # If table did not exist, ignore the error
      raise unless exc[0].sql_code == -206
    end

    # call-seq: obj.setup(connect_string, user_name=nil, password=nil)
    # 
    # Make a single connection for all the test cases, because
    # of the excessive overhead involved to do it once every setup call.
    #
    def setup(*args)
      unless args.empty?
        @db ||= Informix.connect(args[0], args[1], args[2])
        @supported = {}
        @supported["boolean"] = supported_data_type?(@db, "boolean")
        @supported["int8"] = supported_data_type?(@db, "int8")

        @rows = [
          [
            1, 'char1'.ljust(30, ' '), 'varchar1', MIN_INT16,
            MIN_INT32, E, PI, DATE, DATE_TIME, INTERVALYM1, INTERVALDS1,
            BIGDECIMAL1, nil
          ],
          [
            2, 'char2'.ljust(30, ' '), 'varchar2', MAX_INT16,
            MAX_INT32, 8.9, 8.9, TODAY.strftime("%m/%d/%Y"),
            NOW.strftime("%Y-%m-%d %H:%M:%S.000"), INTERVALYM2, INTERVALDS2,
            BIGDECIMAL2, TEXT
          ]
        ]

        if @supported["boolean"]
          @rows[0] << 't'
          @rows[1] << 'f'
        end

        if @supported["int8"]
          @rows[0] << MIN_INT64
          @rows[1] << MAX_INT64
        end
        @rows.freeze
      end

    end

    # Override the base class version of default_test() so that
    # a test case with no tests doesn't trigger an error.
    def default_test; end
  end
end

