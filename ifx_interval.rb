# $Id: ifx_interval.rb,v 1.6 2008/03/28 05:15:12 santana Exp $
#
# Copyright (c) 2008, Gerardo Santana Gomez Garrido <gerardo.santana@gmail.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

module Informix
  # Used for sending and retrieving INTERVAL values to/from Informix.
  # It can be used in some expressions with Numeric, Date, DateTime and Time.
  class Interval
    include Comparable

    attr_reader :qual, :val
    attr_reader :years, :months, :days, :hours, :minutes, :seconds

    # Interval.year_to_month(years = 0, months = 0)         =>  interval
    # Interval.year_to_month(:years => yy, :months => mm)   =>  interval
    #
    # Creates an Interval object in the year-to-month scope.
    #
    # Interval.year_to_month(5)                           =>  '5-00'
    # Interval.year_to_month(0, 3)                        =>  '0-03'
    # Interval.year_to_month(5, 3)                        =>  '5-03'
    # Interval.year_to_month(:years => 5.5)               =>  '5-06'
    # Interval.year_to_month(:months =>3)                 =>  '0-03'
    # Interval.year_to_month(:years => 5.5, :months =>5)  =>  '5-11'
    def self.year_to_month(*args)
      if args.size == 1 && Hash === args[0]
        years, months = args[0][:years], args[0][:months]
      elsif args.size <= 2 && args.all? {|e| Numeric === e }
        years, months = args
      else
        raise TypeError, "Expected Numerics or a Hash"
      end
      years ||= 0; months ||= 0
      if ![years, months].all? {|e| Numeric === e && e >= 0 }
        raise ArgumentError, "Expected Numerics >= 0"
      end
      from_months(years*12 + months.to_i)
    end

    def self.from_months(months)
      new(:YEAR_TO_MONTH, months)
    end

    # Interval.day_to_second(days = 0, hours = 0,
    #                        minutes = 0, seconds = 0)          => interval
    # Interval.day_to_second(:days => dd, :hours => hh,
    #                        :minutes => mm, :seconds => ss)    => interval
    #
    # Creates an Interval object in the day-to-second scope.
    #
    # Interval.day_to_second(5, 3)                      # => '5 03:00:00.00000'
    # Interval.day_to_second(0, 2, 0, 30)               # => '0 02:00:30.00000'
    # Interval.day_to_second(:hours=>2.5)               # => '0 02:30:00.00000'
    # Interval.day_to_second(:seconds=>Rational(151,10))# => '0 00:00:15.10000'
    # Interval.day_to_second(:seconds=> 20.13)          # => '0 00:00:20.13000'
    # Interval.day_to_second(:days=>1.5, :hours=>2)     # => '1 14:00:00.00000'
    def self.day_to_second(*args)
      if args.size == 1 && Hash === args[0]
        h = args[0]
        days, hours, minutes, seconds = h[:days], h[:hours], h[:minutes],
                                        h[:seconds]
      elsif args.size <= 5 && args.all? {|e| Numeric === e || e.nil? }
        days, hours, minutes, seconds = args
      else
        raise TypeError, "Expected Numerics or a Hash"
      end
      days ||= 0; hours ||= 0; minutes ||= 0; seconds ||= 0
      if ![days, hours, minutes, seconds].all? {|e| Numeric === e && e >= 0 }
        raise ArgumentError, "Expected Numerics >= 0"
      end
      from_seconds(days*24*60*60 + hours*60*60 + minutes*60 + seconds)
    end

    def self.from_seconds(seconds)
      new(:DAY_TO_SECOND, seconds)
    end

    # Interval.new(qual, val)  =>  interval
    #
    # Creates an Interval object with +qual+ as qualifier and +val+ as value.
    #
    # +qual+ must be either :YEAR_TO_MONTH or :DAY_TO_SECOND
    # +val+ must be either the amount of months or seconds
    def initialize(qual, val)
      raise TypeError, "Expected Numeric" if !(Numeric === val)
      case @qual = qual
      when :YEAR_TO_MONTH
        @val = val.to_i
        @years, @months = @val.abs.divmod 12
        if @val < 0
          @years = -@years
          @months = -@months
        end
        @days = @hours = @minutes = @seconds = 0
      when :DAY_TO_SECOND
        @val = val
        @days, @hours = @val.abs.divmod(24*60*60)
        @hours, @minutes = @hours.divmod(60*60)
        @minutes, @seconds = @minutes.divmod(60)
        if @val < 0
          @days = -@days; @hours = -@hours; @minutes = -@minutes;
          @seconds = -@seconds
        end
        @years = @months = 0
      else
        raise ArgumentError,
             "Invalid qualifier, it must be :YEAR_TO_MONTH or :DAY_TO_SECOND"
      end
    end

    # interval.to_a     => array
    #
    # Returns [ years, months, days, hours, minutes, seconds ]
    def to_a
      [ @years, @months, @days, @hours, @minutes, @seconds ]
    end

    def +@() self end
    def -@() Interval.new(@qual, -@val) end

    # interval + numeric  => interval
    # interval + date     => date
    # interval + datetime => datetime
    # interval + time     => time
    def +(obj)
      case obj
      when Numeric
        Interval.new(@qual, @val + obj)
      when Interval
        return Interval.new(@qual, @val + obj.val) if @qual == obj.qual
        raise ArgumentError, "Incompatible qualifiers"
      when DateTime
        @qual == :YEAR_TO_MONTH ? obj >> @val : obj + @val/86400
      when Date
        return obj >> @val if @qual == :YEAR_TO_MONTH
        raise ArgumentError, "Incompatible qualifiers"
      when Time
        return obj + @val if @qual == :DAY_TO_SECOND
        raise ArgumentError, "Incompatible qualifiers"
      else
        raise TypeError, "Expected Numeric, Interval, Date, DateTime or Time"
      end
    end

    # interval*numeric  => interval
    def *(n)
      return Interval.new(@qual, @val*n) if Numeric === n
      raise TypeError, "Expected Numeric"
    end

    # interval/numeric  => interval
    def /(n)
      return Interval.new(@qual, @val/n) if Numeric === n
      raise TypeError, "Expected Numeric"
    end

    # interval1 <=> interval2  => true or false
    #
    # Compares two compatible Interval objects.
    def <=>(ivl)
      raise ArgumentError, "Incompatible qualifiers" if @qual != ivl.qual
      @val <=> ivl.val
    end

    # invl.to_s   => string
    #
    # Returns an ANSI SQL standards compliant string representation
    def to_s
      if @qual == :YEAR_TO_MONTH # YYYY-MM
        "%d-%02d" % [@years, @months.abs]
      else # DD HH:MM:SS.F
        "%d %02d:%02d:%08.5f" % [@days, @hours.abs, @minutes.abs, @seconds.abs]
      end
    end

    # invl.to_years  => numeric
    #
    # Converts a YEAR TO MONTH Interval object into years
    def to_years
      raise "Not applicable" if @qual != :YEAR_TO_MONTH
      if Rational === @val
        @val/12
      else
        @val/12.0
      end
    end

    # invl.to_months  => numeric
    #
    # Converts a YEAR TO MONTH Interval object into months
    def to_months
      raise "Not applicable" if @qual != :YEAR_TO_MONTH
      @val
    end

    # invl.to_days  => numeric
    #
    # Converts a DAY TO SECOND Interval object into days
    def to_days
      raise "Not applicable" if @qual != :DAY_TO_SECOND
      if Rational === @val
        @val/60/60/24
      else
        @val/60.0/60/24
      end
    end

    # invl.to_hours  => numeric
    #
    # Converts a DAY TO SECOND Interval object into hours
    def to_hours
      raise "Not applicable" if @qual != :DAY_TO_SECOND
      if Rational === @val
        @val/60/60
      else
        @val/60.0/60
      end
    end

    # invl.to_minutes  => numeric
    #
    # Converts a DAY TO SECOND Interval object into minutes
    def to_minutes
      raise "Not applicable" if @qual != :DAY_TO_SECOND
      if Rational === @val
        @val/60
      else
        @val/60.0
      end
    end

    # invl.to_seconds  => numeric
    #
    # Converts a DAY TO SECOND Interval object into seconds
    def to_seconds
      raise "Not applicable" if @qual != :DAY_TO_SECOND
      @val
    end

  end # class Interval
end # module Informix
