# -*- coding: utf-8 -*-
require 'webrick'
require 'webrick/cgi'
require 'drb/drb'
require 'erb'
require 'savon'

class SavonApp
  def initialize(book)
    @book = book
    @ui = UI.new(@book)
  end
  attr_reader :book, :ui

  class Page
    def initialize(name)
      @name = name
    end
    attr_reader :name, :src, :html, :warnings, :title

    def set_src(text)
      @src = text
      km = Kramdown::Document.new(text)
      @title = fetch_title(km) || @name
      @html = km.to_html
      @warnings = km.warnings
    end

    def fetch_title(km)
      header = km.root.children.find {|x| x.type == :header}
      return nil unless header
      text = header.children.find {|x| x.type == :text}
      return nil unless text
      text.value
    end
  end

  class UI < WEBrick::CGI
    include ERB::Util
    extend ERB::DefMethod
    def_erb_method('to_html(field, result)', ERB.new(<<EOS))
<html>
 <head>
  <title><%=h field.join(' ') %></title>
 </head>
 <body>
  <pre>
  <%=h result.to_a %>
  </pre>
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
      do_GET(req, res)
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
      res.body = to_html(* @book.page(req.path_info))
    end
  end
end

if __FILE__ == $0
  book = Savon::Book.new(ARGV.shift)
  app = SavonApp.new(book)
  DRb.start_service('druby://localhost:50830', app.ui)
  DRb.thread.join
end
