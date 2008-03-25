# $Id: ifx_interval.rb,v 1.2 2008/03/25 04:28:34 santana Exp $
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
  # Used for sending and retrieving INTERVAL values to/from Informix
  class Interval
    include Comparable

    attr_reader :qual, :val

    # Interval.year_to_month(years, months)  =>  interval
    #
    # Creates an Interval object in the year-to-month scope.
    def self.year_to_month(years, months = 0)
      new(:YEAR_TO_MONTH, years*12 + months)
    end

    def self.from_months(months)
      new(:YEAR_TO_MONTH, months)
    end

    # Interval.day_to_fraction(days, hours, mins, secs, frac)  =>  interval
    #
    # Creates an Interval in the day-to-fraction scope.
    # Use a Rational if you want to specify fraction of seconds.
    def self.day_to_fraction(days, hours = 0, minutes = 0,
                             seconds = 0, fraction = 0)
      new(:DAY_TO_FRACTION, days*24*60*60 + hours*60*60 + minutes*60 +
                            seconds + fraction)
    end

    def self.from_seconds(seconds)
      new(:DAY_TO_FRACTION, seconds)
    end

    # Interval.new(qual, val)  =>  interval
    #
    # Creates an Interval object with +qual+ as qualifier and +val+ as value.
    #
    # +qual+ can be :YEAR_TO_MONTH or :DAY_TO_SECOND
    # +val+ can be the number (Integer or Rational only) of months or seconds
    def initialize(qual, val)
      if !(Integer === val || Rational === val)
        raise TypeError, "Expected Integer or Rational"
      end
      case @qual = qual
      when :YEAR_TO_MONTH
        @val = Integer(val)
      when :DAY_TO_FRACTION
        @val = val.to_r
      else
        raise ArgumentError, "Invalid qualifier, it mus be :YEAR_TO_MONTH or :DAY_TO_FRACTION"
      end
    end

    # interval.to_a     => array
    #
    # Returns [ years, months, days, hours, minutes, seconds, fraction ]
    # setting to nil the fields that don't apply
    def to_a
      update
      [ @years, @months, @days, @hours, @minutes, @seconds, @fraction ]
    end

    def +@() self end
    def -@() Interval.new(@qual, -@val) end

    # interval + integer  => interval
    # interval + rational => interval
    # interval + date     => date
    # interval + datetime => datetime
    # interval + time     => time
    def +(obj)
      case obj
      when Integer, Rational
        Interval.new(@qual, @val + obj)
      when Interval
        raise ArgumentError, "Incompatible qualifiers" if @qual != obj.qual
        Interval.new(@qual, @val + obj.val)
      when DateTime
        @qual == :YEAR_TO_MONTH ? obj >> @val : obj + @val.to_r/86400
      when Date
        return obj >> @val if @qual == :YEAR_TO_MONTH
        raise ArgumentError, "Incompatible qualifiers"
      when Time
        return obj + @val if @qual == :DAY_TO_FRACTION
        raise ArgumentError, "Incompatible qualifiers"
      else
        raise TypeError, "Expected Integer, Rational, Interval, Date, DateTime or Time"
      end
    end

    # interval * integer  => interval
    # interval * rational => interval
    def *(n)
      case n
      when Integer, Rational
        Interval.new(@qual, @val*n)
      else
        raise TypeError, "Expected Integer or Rational"
      end
    end

    # interval / integer  => interval
    # interval / rational => interval
    def /(n)
      case n
      when Integer, Rational
        Interval.new(@qual, @val/n)
      else
        raise TypeError, "Expected Integer or Rational"
      end
    end

    # interval1 <=> interval2  => true or false
    #
    # Compares two compatible Interval objects.
    def <=>(ivl)
      raise ArgumentError, "Incompatible qualifiers" if @qual != ivl.qual
      @val <=> ivl.val
    end

    def to_s
      update
      if @qual == :YEAR_TO_MONTH # YYYY-MM
        "#{"-" if @val < 0}#{@years.abs}-#{@months.abs}"
      else # DD HH:MM:SS.F
        "#{"-" if @val < 0}#{@days.abs} #{@hours.abs}:#{@minutes.abs}:#{(@seconds+@fraction).abs.to_f}"
      end
    end

    private
    def update
      if @qual == :YEAR_TO_MONTH
        @years, @months = @val.abs.divmod 12
        if @val < 0
          @years = -@years
          @months = -@months
        end
      else
        @days, @hours = @val.abs.divmod(60*60*24)
        @hours, @minutes = @hours.divmod(60*60)
        @minutes, @seconds = @minutes.divmod(60)
        @seconds, @fraction = @seconds.divmod(1)
        if @val < 0
          @hours = -@hours; @minutes = -@minutes; @seconds = -@seconds
          @fraction = -@fraction
        end
      end
    end

  end # class Interval
end # module Informix
