require 'pp'
require 'drb'

module Savon
  class MyData
    def initialize(fname)
      @head = []
      @table = []
      @view = {}

      File.open(fname) do |fp|
        line = fp.gets
        @head = heading(line.chomp)
        while line = fp.gets
          @table << row(line.chomp)
        end
      end
    end
    attr_reader :head, :table

    def at(ary, idx)
      it = ary[idx]
      it.nil? || it.empty? ? [nil] : it
    end

    def build_view(name)
      fields = @view[name][0]
      if String === fields
        idx = head.index(fields)
        [method(:eval_simple_view), [idx, @view[name][1]]]
      else
        idx = fields.collect {|s| head.index(s)}
        [method(:eval_view), [idx, @view[name][1]]]
      end
    end

    def eval_simple_view(ary, idx, proc)
      at(ary, idx).collect do |it|
        proc.call(it)
      end
    end

    def eval_view(ary, idxes, proc)
      src = idxes.collect do |idx|
        at(ary, idx)
      end
      proc.call(src)
    end

    def each_row(*field_name)
      field = field_name.collect do |s|
        if @view[s]
          build_view(s)
        else
          idx = head.index(s)
          [method(:at), [idx]]
        end
      end
      @table.each do |q|
        it = field.collect do |m, arg|
          m.call(q, *arg)
        end
        yield(it)
      end
    end

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
    
    def add_view(name, fields, &proc)
      @view[name] = [fields, proc]
    end
  end

  class ResultCache
    def initialize(src)
      @src = src
      @bins = {}
    end

    def clear
      @bins = {}
    end
    
    def [](*field)
      return @bins[field] if @bins[field]
      bin = Bin.new
      @src.each_row(*field) do |ary|
        head, *rest = ary
        head.product(*rest) {|value| bin.emit(* value)}
      end
      @bins[field] = bin
    end
  end

  class Bin
    include Enumerable
    def initialize
      @hash = Hash.new(0)
      @size = 0
    end
    attr_reader :size

    def emit(*arg)
      @hash[arg] += 1
      @size += 1
    end
    
    def each
      @hash.each do |k, v|
        yield k, v
      end
    end

    def sort_by_freq
      sort_by {|k, v| - v}
    end

    INF=1.0/0
    def sort(nil_as=INF)
      sort_by {|k, v| k.collect {|y| y ? y : nil_as}}
    end
  end

  class Book
    def initialize(fname)
      @data = MyData.new(fname)
      @result = ResultCache.new(@data)
    end
    attr_reader :result
    
    def header; @data.head; end

    def page(name)
      field = name.split('/')
      return field, (@result[*field] rescue nil)
    end
    
    def add_view(name, fields, &proc)
      @data.add_view(name, fields, &proc)
      @result.clear
    end
  end

  class Front
    include DRbUndumped
    def initialize(book)
      @book = book
      @legend = {}
    end
    attr_reader :legend

    def set_legend(field, assoc)
      @legend[field] = assoc
    end

    def [](path)
      return @book.page(path)
    end
    
    def add_view(name, fields, &proc)
      @book.add_view(name, fields, &proc)
    end
  end
end

if __FILE__ == $0
  book = Savon::Book.new(ARGV.shift)
  result = book.result
  pp result['F1'].sort
  pp result['F1', 'F2'].sort_by_freq
  pp book.page('F1/F2')
  pp book.page('F1/F30')
  book.add_view('Q2_2V', ['Q2_1', 'Q2_2']) do |req|
    req[1].collect do |it|
      case it
      when 1, 2
        1
      when 4, 5
        2
      else
        0
      end
    end
  end
  pp result['Q2_2V'].sort
  book.add_view('Q2_2R', 'Q2_2') do |value|
    case value
    when 4, 5
      1
    when 1, 2
      2
    else
      0
    end
  end
  pp result['Q2_2R'].sort
end

