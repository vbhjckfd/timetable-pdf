require 'sinatra/base'
require 'rackup'
require 'digest'
require 'uri'
require 'net/http'
require 'tempfile'
# Load thin fully before Rackup resolves its handler; the handler file alone
# does not pull in Thin::Logging (thin 2.0.1).
require 'thin'

class App < Sinatra::Base

  set :server, 'thin'
  set :bind, '0.0.0.0'

  # The stop code reaches a subprocess argument and a file path, so keep it to
  # characters that can mean nothing in either.
  STOP_CODE = /\A[A-Za-z0-9_-]{1,32}\z/.freeze

  # Route overrides handed straight to timetable-offline, which owns what the
  # names mean. Route names are alphanumeric in both alphabets (A47, Т25, А03,
  # Аеропорт), so a comma-separated list of those is all that is ever forwarded.
  ROUTE_PARAMS = %w[only add remove].freeze
  ROUTE_LIST = /\A[[:alnum:]]{1,16}(,[[:alnum:]]{1,16})*\z/.freeze

  OFFLINE = ENV.fetch('OFFLINE_URL', 'https://offline.lad.lviv.ua')

  helpers do
    def stop_code!
      params['code'].tap { |code| halt 404 unless STOP_CODE.match?(code) }
    end

    def overrides
      ROUTE_PARAMS.each_with_object({}) do |name, h|
        # Rack can hand the value back tagged binary, and [[:alnum:]] only knows
        # about Cyrillic route names on a UTF-8 string.
        value = params[name].to_s.dup.force_encoding(Encoding::UTF_8)
        next if value.empty?
        halt 400, "Bad #{name} parameter" unless value.valid_encoding? && ROUTE_LIST.match?(value)

        h[name] = value
      end
    end

    def offline_url(path)
      url = "#{OFFLINE}#{path}"
      overrides.any? ? "#{url}?#{URI.encode_www_form(overrides)}" : url
    end

    # The overrides change what is drawn, so they have to change the cache path
    # too, or one route set is served under another's name.
    def pdf_path(stop_code, url, kind)
      "/tmp/#{stop_code}-#{kind}-#{Digest::SHA256.hexdigest(url)[0, 16]}.pdf"
    end

    # Argument list, not a command string: no shell, nothing to quote-escape.
    def wkhtmltopdf(*options, source, file_path)
      system('wkhtmltopdf', '-q', '-B', '0', '-L', '0', '-R', '0', '-T', '0', *options, source, file_path)
    end

    def send_pdf(file_path, filename)
      # .pdf is on Cloudflare's default cacheable-extension list, so without a
      # header of our own the edge holds a stop's PDF for a day — long enough to
      # outlive an edit to the route list, or to the stop's routes upstream.
      cache_control :no_store
      content_type 'application/pdf'
      send_file(file_path, :disposition => 'attachment', :filename => filename)
    end
  end

  get '/:code.pdf' do
    stop_code = stop_code!
    url = offline_url("/#{stop_code}")
    file_path = pdf_path(stop_code, url, 'stop')

    ok = wkhtmltopdf('--page-height', '310mm', '--page-width', '460mm',
                     '--zoom', '0.35', '--disable-external-links',
                     url, file_path)

    halt 502, 'Не вдалося згенерувати PDF' unless ok && File.exist?(file_path)

    send_pdf(file_path, "#{stop_code}.pdf")
  end

  # The network poster, 8386x7205, fitted to the height of an A1 sheet. wkhtmltopdf
  # does not scale a bare SVG document to the page (--zoom has no effect on it), so
  # the SVG is set inline in an HTML page at full width.
  SCHEMA_PAGE = %w[--page-width 691.4mm --page-height 594mm].freeze

  get '/:code/schema.pdf' do
    stop_code = stop_code!
    url = offline_url("/#{stop_code}/schema")
    file_path = pdf_path(stop_code, url, 'schema')

    uri = URI(url)
    response = begin
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 20) do |http|
        http.get(uri.request_uri)
      end
    rescue StandardError => e
      warn "schema fetch failed for stop #{stop_code}: #{e.class}: #{e.message}"
      halt 502, 'Не вдалося отримати схему'
    end
    halt response.code.to_i, 'Немає такої зупинки' if %w[400 404].include?(response.code)
    halt 502, 'Не вдалося отримати схему' unless response.is_a?(Net::HTTPSuccess)

    svg = response.body.force_encoding(Encoding::UTF_8)
    svg = svg[svg.index('<svg')..] if svg.index('<svg')
    # QtWebKit does not size an inline SVG's height from its viewBox: with only
    # width="100%" it lays the drawing out zero pixels tall and prints a blank
    # page. The SVG fills a box that keeps the viewBox's aspect ratio instead.
    view_box = svg[/<svg\b[^>]*?\sviewBox="([^"]*)"/m, 1].to_s.split.map(&:to_f)
    ratio = view_box.size == 4 && view_box[2].positive? ? view_box[3] / view_box[2] : 1
    svg = svg.sub(/<svg\b([^>]*?)\swidth="[^"]*"\s+height="[^"]*"/m, '<svg\\1 width="100%" height="100%"')
    # Absolute badge URLs rather than a <base>: a <base> would also re-root the
    # drawing's url(#...) gradient and clip references, and they would stop resolving.
    svg = svg.gsub('xlink:href="/', %(xlink:href="#{OFFLINE}/))

    html = Tempfile.new(['schema', '.html'])
    begin
      html.write(<<~HTML)
        <!doctype html><html><head><meta charset="utf-8">
        <style>html,body{margin:0;padding:0}#poster{position:relative;height:0;padding-bottom:#{(ratio * 100).round(4)}%}
        #poster>svg{display:block;position:absolute;top:0;left:0}</style></head>
        <body><div id="poster">#{svg}</div></body></html>
      HTML
      html.close
      ok = wkhtmltopdf(*SCHEMA_PAGE, '--enable-local-file-access', '--disable-external-links',
                       html.path, file_path)
    ensure
      html.unlink
    end

    halt 502, 'Не вдалося згенерувати PDF' unless ok && File.exist?(file_path)

    send_pdf(file_path, "#{stop_code}-schema.pdf")
  end
end

App.run!