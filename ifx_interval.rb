# $Id: ifx_interval.rb,v 1.3 2008/03/27 09:28:20 santana Exp $
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
      years ||= 0
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
    # Interval.day_to_second(5, 3)                      # => '5 3:00:00.00000'
    # Interval.day_to_second(0, 2, 0, 30)               # => '0 2:00:30.00000'
    # Interval.day_to_second(:hours=>2.5)               # => '0 2:30:00.00000'
    # Interval.day_to_second(:seconds=> 10.16)          # => '0 0:00:10.16000'
    # Interval.day_to_second(:days=>1.5, :hours=>2)     # => '1 14:00:0.00000'
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
      @val = case @qual = qual
             when :YEAR_TO_MONTH
               val.to_i
             when :DAY_TO_SECOND
               val
             else
               raise ArgumentError,
                "Invalid qualifier, it must be :YEAR_TO_MONTH or :DAY_TO_SECOND"
             end
    end

    # interval.to_a     => array
    #
    # Returns [ years, months, days, hours, minutes, seconds ]
    # setting to nil the fields that do not apply
    def to_a
      update
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

    def to_s
      update
      if @qual == :YEAR_TO_MONTH # YYYY-MM
        "%d-%02d" % [@years, @months.abs]
      else # DD HH:MM:SS.F
        "%d %02d:%02d:%02.5f" % [@days, @hours.abs, @minutes.abs, @seconds.abs]
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
        @days, @hours = @val.abs.divmod(24*60*60)
        @hours, @minutes = @hours.divmod(60*60)
        @minutes, @seconds = @minutes.divmod(60)
        if @val < 0
          @days = -@days; @hours = -@hours; @minutes = -@minutes;
          @seconds = -@seconds
        end
      end
    end

  end # class Interval
end # module Informix
