require 'pp'

module Savon
  class MyData
    def initialize(fname)
      @head = []
      @table = []

      File.open(fname) do |fp|
        line = fp.gets
        @head = heading(line.chomp)
        while line = fp.gets
          @table << row(line.chomp)
        end
      end
    end
    attr_reader :head, :table

    def size
      @table.size
    end
    
    def short_data
      sz = @head.size
      @table.find_all {|it| it.size != sz}
    end
    
    def heading(line)
      line.split("\t")
    end
    
    def row(line)
      line.split("\t").collect do |s|
        s.split(",").collect do |ss|
          Integer(ss) rescue ss
        end
      end
    end
  end

  class ResultCache
    def initialize(src)
      @src = src
      @bins = {}
    end
    
    def [](*field)
      return @bins[field] if @bins[field]
      bin = Bin.new
      @src.table.each do |q|
        head, *rest = field.collect {|f| q[f] || [nil]}
        head.product(*rest) {|value| bin.emit(* value)}
      end
      @bins[field] = bin
    end
  end

  class Bin
    include Enumerable
    def initialize
      @hash = Hash.new {|h, k| h[k] = 0}
      @size = 0
    end
    attr_reader :size

    def emit(*arg)
      @hash[arg] += 1
      @size += 1
    end
    
    def each
      @hash.each do |k, v|
        yield k + [v]
      end
    end

    def sort_by_freq
      sort_by {|x| - x[-1]}
    end

    INF=1.0/0
    def sort(nil_as=INF)
      sort_by {|x| x.collect {|y| y ? y : nil_as}}
    end
  end

  class Book
    def initialize(fname)
      @data = MyData.new(fname)
      @result = ResultCache.new(@data)
    end
    attr_reader :result
    
    def header; @data.head; end
  end
end

if __FILE__ == $0
  book = Savon::Book.new('data.txt')
  result = book.result
  pp result[1, 2, 10]
end

