#--
# Copyright (c) 2008-2016, Gerardo Santana Gomez Garrido <gerardo.santana@gmail.com>
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
#++

module Informix
  # The +IntervalBase+ class is used for sending and retrieving INTERVAL
  # values to/from Informix.
  #
  # It can be used in some expressions with +Numeric+, +Date+, +DateTime+ and
  # +Time+.
  class IntervalBase
    include Comparable

    attr_reader :val

    # IntervalBase.new(val)  =>  interval
    #
    # Creates an +Interval+ object with +val+ as value.
    def initialize(val)
      return @val = val if Numeric === val
      raise TypeError, "Expected Numeric" 
    end

    def +@; self end
    def -@; self.class.new(-@val) end

    # Adds an +Interval+ object to a +Numeric+ or another compatible +Interval+
    #
    #   interval + numeric  => interval
    #   interval + interval => interval
    def +(obj)
      case obj
      when Numeric
        self.class.new(@val + obj)
      when self.class
        self.class.new(@val + obj.val)
      else
        raise TypeError, "#{self.class} cannot be added to #{obj.class}"
      end
    end

    # Multiplies an +Interval+ object by a +Numeric+
    #
    #   interval*numeric  => interval
    def *(n)
      return self.class.new(@val*n) if Numeric === n
      raise TypeError, "Expected Numeric"
    end

    # Divides an +Interval+ object by a +Numeric+
    #
    #   interval/numeric  => interval
    def /(n)
      return self.class.new(@val/n) if Numeric === n
      raise TypeError, "Expected Numeric"
    end

    # Compares two compatible +Interval+ objects.
    #
    #   interval1 <=> interval2  => true or false
    def <=>(ivl)
      return @val <=> ivl.val if self.class === ivl
      raise ArgumentError, "Incompatible qualifiers"
    end

    # Returns the fields of an +Interval+ object as an +Array+
    #
    #   invl.to_a   => array
    def to_a; @fields end

  end # class IntervalBase

  # The +IntervalYTM+ class is an Interval class dedicated only to
  # represent intervals in the scope YEAR TO MONTH.
  class IntervalYTM < IntervalBase
    attr_reader :years, :months

    # Creates an IntervalYTM object with +val+ as value.
    #
    #   IntervalYTM.new(val)  =>  interval
    def initialize(val)
      super
      @val = val.to_i
      @years, @months = @val.abs.divmod 12
      if @val < 0
        @years = -@years
        @months = -@months
      end
      @fields = [ @years, @months ]
    end

    #   interval + date     => date
    #   interval + datetime => datetime
    def +(obj)
      case obj
      when Date, DateTime
        obj >> @val
      else
        super
      end
    end

    # Returns an ANSI SQL standards compliant string representation
    #
    #   invl.to_s   => string
    def to_s; "%d-%02d" % [@years, @months.abs] end

    # Converts a invl to years
    #
    #   invl.to_years  => numeric
    def to_years; Rational === @val ? @val/12 : @val/12.0 end

    # Converts invl to months
    #
    #   invl.to_months  => numeric
    def to_months; @val end
  end # class IntervalYTM

  # The +IntervalDTS+ class is an Interval class dedicated only to
  # represent intervals in the scope DAY TO SECOND.
  class IntervalDTS < IntervalBase
    attr_reader :days, :hours, :minutes, :seconds

    # Creates an IntervalDTS object with +val+ as value.
    #
    #   IntervalDTS.new(val)  =>  interval
    def initialize(val)
      super
      @days, @hours = @val.abs.divmod(24*60*60)
      @hours, @minutes = @hours.divmod(60*60)
      @minutes, @seconds = @minutes.divmod(60)
      if @val < 0
        @days = -@days; @hours = -@hours; @minutes = -@minutes;
        @seconds = -@seconds
      end
      @fields = [ @days, @hours, @minutes, @seconds ]
    end

    #   interval + datetime => datetime
    #   interval + time     => time
    def +(obj)
      case obj
      when DateTime
        obj + (Rational === @val ? @val/86400 : @val/86400.0)
      when Time
        obj + @val
      else
        super
      end
    end

    # Returns an ANSI SQL standards compliant string representation
    #
    #   invl.to_s   => string
    def to_s
      "%d %02d:%02d:%08.5f" % [@days, @hours.abs, @minutes.abs, @seconds.abs]
    end

    # Converts invl to days
    #
    #   invl.to_days  => numeric
    def to_days; Rational === @val ? @val/60/60/24 : @val/60.0/60/24 end

    # Converts invl to hours
    #
    #   invl.to_hours  => numeric
    def to_hours; Rational === @val ? @val/60/60 : @val/60.0/60 end

    # Converts invl to minutes
    #
    #   invl.to_minutes  => numeric
    def to_minutes; Rational === @val ? @val/60 : @val/60.0 end

    # Converts invl to seconds
    #
    #   invl.to_seconds  => numeric
    def to_seconds; @val end
  end # class IntervalDTS

  # The +Interval+ module provides shortcuts for creating +IntervalYTM+ and
  # +IntervalDTS+ objects
  module Interval
    # Shortcut to create an IntervalYTM object.
    #
    #   Interval.year_to_month(years = 0, months = 0)       =>  interval
    #   Interval.year_to_month(:years => yy, :months => mm) =>  interval
    #
    #   Interval.year_to_month(5)                           #=>  '5-00'
    #   Interval.year_to_month(0, 3)                        #=>  '0-03'
    #   Interval.year_to_month(5, 3)                        #=>  '5-03'
    #   Interval.year_to_month(:years => 5.5)               #=>  '5-06'
    #   Interval.year_to_month(:months => 3)                #=>  '0-03'
    #   Interval.year_to_month(:years => 5.5, :months => 5) #=>  '5-11'
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

    # Shortcut to create an IntervalYTM object.
    #
    #   Interval.from_months(3)   #=>  '0-03'
    #   Interval.from_months(71)  #=>  '5-11'
    def self.from_months(months)
      IntervalYTM.new(months)
    end

    # Shortcut to create an IntervalDTS object.
    #
    #   Interval.day_to_second(days = 0, hours = 0,
    #                          minutes = 0, seconds = 0)          => interval
    #   Interval.day_to_second(:days => dd, :hours => hh,
    #                          :minutes => mm, :seconds => ss)    => interval
    #
    #   Interval.day_to_second(5, 3)                      # => '5 03:00:00.00000'
    #   Interval.day_to_second(0, 2, 0, 30)               # => '0 02:00:30.00000'
    #   Interval.day_to_second(:hours=>2.5)               # => '0 02:30:00.00000'
    #   Interval.day_to_second(:seconds=>Rational(151,10))# => '0 00:00:15.10000'
    #   Interval.day_to_second(:seconds=> 20.13)          # => '0 00:00:20.13000'
    #   Interval.day_to_second(:days=>1.5, :hours=>2)     # => '1 14:00:00.00000'
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

    # Shortcut to create an IntervalDTS object.
    #
    #   Interval.from_seconds(9000)               #=> '0 02:30:00.00000'
    #   Interval.from_seconds(Rational(151, 10))  #=> '0 00:00:15.10000'
    def self.from_seconds(seconds)
      IntervalDTS.new(seconds)
    end
  end # module Interval
end # module Informix
