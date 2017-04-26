# Ruby/Informix -- Ruby library for connecting to IBM Informix.

## Motivation
Read about [the situation that started it all](http://santanatechnotes.blogspot.com/2006/03/informix-driver-for-ruby.html).

## Download

The latest version of Ruby/Informix can be found at http://rubyforge.org/projects/ruby-informix

## Supported platforms

Ruby/Informix has been tested succesfully with Informix 7 and above, and
Informix CSDK 2.81 and above, on the following platforms:

    Operating System     Architecture
    -----------------------------------------
    Solaris              SPARC64      
    Mac OS X             x86-64
    GNU/Linux            x86, x86-64
    Windows XP/2000      x86
    HP-UX 11.11          PA-RISC 2.0 64-bit

Send me an e-mail if you have [un]succesfully tested Ruby/Informix on another
platform.

## Installation

### Requirements

* Informix CSDK 2.81 or above

If you want to build Ruby/Informix instead of installing a precompiled gem,
you will also need:

* Microsoft Visual Studio 6.0, for Windows or
* an ANSI C compiler, for UNIX and Linux

### Rubygem installation

    gem install ruby-informix

### From source

Set your INFORMIXDIR environment variable and run:

    rake gem
    sudo -E gem install ruby-informix*.gem

## Documentation

RDoc and ri documentation is automatically installed. It can also be found
[online](http://ruby-informix.rubyforge.org/doc)

## Examples

*Note*: set LD\_LIBRARY\_PATH (non-macOS) or DYLD\_LIBRARY\_PATH (macOS) to
search in $INFORMIXDIR/lib and $INFORMIXDIR/lib/esql before loading the gem.

### Connecting to a database

    db = Informix.connect('stores')

### Traversing a table

    db.foreach('select * from stock') do |r|
      # do something with the record
    end

### Fetching all records from a table

    records = db.cursor('select * from stock') do |cur|
      cur.open
      cur.fetch_all
    end

### Inserting records

    stmt = db.prepare('insert into state values(?, ?)')
    stmt.execute('CA', 'California')
    stmt.call('NM', 'New Mexico')
    stmt['TX', 'Texas']

### Iterating over a table using a hash (shortcut)

    db.foreach_hash('select * from customers') do |cust|
      puts "#{cust['firstname']} #{cust['lastname']}"
    end

More examples can be found at:

http://ruby-informix.rubyforge.org/examples.html


## Data types supported

    Informix                          Ruby
    --------------------------------------------------------
    SMALLINT, INT, INT8, FLOAT,      Numeric
    SERIAL, SERIAL8
    CHAR, NCHAR, VARCHAR, NVARCHAR   String
    DATE                             Date
    DATETIME                         Time
    INTERVAL                         Informix::IntervalYTM,
                                     Informix::IntervalDTS
    DECIMAL, MONEY                   BigDecimal
    BOOL                             TrueClass, FalseClass
    BYTE, TEXT                       StringIO, String
    CLOB, BLOB                       Informix::Slob


NULL values can be inserted and are retrieved as +nil+.

Any IO-like object that provides a read method, e.g. StringIO or File objects,
can be used to insert data in BYTE or TEXT fields. Data retrieved from
BYTE and TEXT fields are stored in String objects.

Strings can be used where Informix accepts them for non-character data types,
like DATE, DATETIME, INTERVAL, BOOL, DECIMAL and MONEY


## Recommendations

* Use blocks to release Informix resources automatically as soon as possible.
  Alternatively, use #free.
* You can optimize cursor execution by changing the size of fetch and insert
  buffers, setting the environment variable FET\_BUF\_SIZE to up to 32767.


## Support

Feel free to send me bug reports, feature requests, comments, patches or
questions directly to my mailbox or via github.

## Presentations and articles about Ruby/Informix

* [Talking with Perl, PHP, Python, Ruby to IDS](http://www.informix-zone.com/informix-script-dbapi), Eric Herber, The Informix Zone.
* [Informix on Rails](http://www.ibm.com/developerworks/blogs/page/gbowerman?entry=informix_on_rails), Guy Bowerman, IBM developerWorks Blogs: Informix Application Development.
* [Ruby/Informix, and the Ruby Common client](http://www.ibm.com/developerworks/blogs/page/gbowerman?entry=ruby_informix_and_the_ruby), Guy Bowerman, IBM developerWorks Blogs: Informix Application Development.
* [Using IBM Informix Dynamic Server on Microsoft Windows, Part 6](http://www.ibm.com/developerworks/offers/lp/demos/summary/usingids6.html), Akmal B. Chaudhri, IBM developerWorks: On demand demos.

## License

Ruby/Informix is available under the three-clause BSD license
