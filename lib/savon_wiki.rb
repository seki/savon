# -*- coding: utf-8 -*-
require 'kramdown'
require 'webrick'
require 'webrick/cgi'
require 'drb/drb'
require 'erb'
require 'monitor'
require 'pp'
require 'drip'
require 'savon'

module Kramdown
  module Converter
    class Savon < Html
      include ERB::Util
      def convert_codeblock(el, any)
        box = Thread.current[:savon_wiki]
        box.eval_codeblock(el.value)
      rescue Exception
        '<pre>' + h($!.inspect) + '</pre>'
      end
    end
  end
end

class SavonWiki
  def initialize(savon, dbname='savon')
    @storage = Storage.new(dbname)
    @book = Book.new(savon, @storage)
    @ui = UI.new(@book)
  end
  attr_reader :book, :savon
  
  def start(env, stdin, stdout)
    @ui.start(env, stdin, stdout)
  end

  class Storage
    def initialize(name)
      @drip = Drip.new(name)
    end
    
    def [](key)
      it ,= @drip.head(1, tag(key))
      return nil unless it
      it[1]
    end
    
    def []=(key, value)
      @drip.write(value, tag(key))
    end

    def tag(key)
      "savon:#{key}"
    end
  end

  class Book
    include MonitorMixin
    def initialize(savon, storage)
      super()
      @page = {}
      @storage = storage
      @savon = savon
    end

    def [](name)
      @page[name] || Page.new(self, name, @storage[name])
    end

    def []=(name, src)
      synchronize do
        page = self[name]
        @page[name] = page
        @storage[name] = src
        page.set_src(src)
      end
    end

    def savon_box
      SavonBox.new(@savon)
    end
  end

  class Page
    def initialize(book, name, src)
      @book = book
      @name = name
      set_src(src || "# #{name}\n\nan empty page. edit me.")
    end
    attr_reader :name, :src, :html, :warnings, :title

    def set_src(text)
      @src = text
      km = Kramdown::Document.new(text)
      @title = fetch_title(km) || @name
      Thread.current[:savon_wiki] = @book.savon_box
      @html = km.to_savon
      Thread.current[:savon_wiki] = nil
      @warnings = km.warnings
    end

    def fetch_title(km)
      header = km.root.children.find {|x| x.type == :header}
      return nil unless header
      text = header.children.find {|x| x.type == :text}
      return nil unless text
      text.value
    end

    def codeblock(root)
      if root.type == :codeblock
        pp root
        root.type = :text
        root.value = 'replaced'
      end
      root.children.each do |x|
        codeblock(x)
      end
    end
  end

  class UI < WEBrick::CGI
    include ERB::Util
    extend ERB::DefMethod
    def_erb_method('to_html(page)', ERB.new(<<EOS))
<html>
 <head>
  <title><%=h page.title%></title>
  <script language="JavaScript">
function open_edit(){
document.getElementById('edit').style.display = "block";
}
  </script>
 </head>
 <body>
  <a href='javascript:open_edit()'>[edit]</a>
  <div id='edit' style='display:none;' width=90%>
   <form method='post'>
    <input type='submit' name='ok' value='ok'/><br />
    <textarea name='text' rows="20" cols="80"><%=h page.src %></textarea>
   </form>
  </div>
  <%= page.html %>
 </body>
</html>
EOS

    def initialize(book, *args)
      super(*args)
      @book = book
    end

    def redirect_if_necessary(req, res)
      return unless  req.path_info == ''
      res.set_redirect(WEBrick::HTTPStatus::MovedPermanently,
                       req.request_uri.to_s + '/')
    end

    def do_GET(req, res)
      redirect_if_necessary(req, res)      
      build_page(req, res)
    end

    def do_POST(req, res)
      redirect_if_necessary(req, res)      
      do_request(req, res)
      build_page(req, res)
    end

    def do_request(req, res)
      text ,= req.query['text']
      return if text.nil? || text.empty?
      text = text.force_encoding('utf-8')
      @book[req.path_info] = text
    rescue
    end

    def build_page(req, res)
      res['content-type'] = 'text/html; charset=utf-8'
      res.body = to_html(@book[req.path_info])
    end
  end

  class SavonBox
    include ERB::Util
    def initialize(context)
      @savon = context
      @legend = {}
    end
    
    def eval_codeblock(value)
      eval(value, binding)
    end

    def report(path, freq)
      head, result = @savon[path]

      sorted = freq ? result.sort_by_freq : result.sort

      it = sorted.collect do |k, v|
        [k.zip(head).collect {|value, name|
           legend = @legend[name] || @savon.legend[name]
           if legend
             if value
               legend[value] || value
             else
               legend[0]
             end
           else
             value
           end
         }, v
        ]
      end

      [head + [result.size]] + it
    end

    def default_legend(field, assoc)
      @savon.set_legend(field, assoc)
    end

    def legend(field, assoc)
      @legend[field] = assoc
    end

    ERB.new(<<EOS).def_method(self, 'table(path, freq=false)')
<table><%
   head, *rest = report(path, freq)
pp rest
%><div class="savontable"><tr><%
   head.each {|x| %><th><%=h x%></th><% } %></tr><%
   rest.each {|r| 
     %><tr><% r[0].each {|x|
       %><th><%=h x%></th><%
     }%><td><%=h r[1]%></td></tr><%
   }
 %></table></div>
EOS

    def add_view(name, fields, &proc)
      @savon.add_view(name, fields, &proc)
    end
  end
end

if __FILE__ == $0
  savon = Savon::Book.new(ARGV.shift)
  front = Savon::Front.new(savon)
  wiki = SavonWiki.new(front)

  DRb.start_service('druby://localhost:50830', wiki)
  DRb.thread.join
end



