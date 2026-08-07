require 'sinatra/base'
require 'rackup'
require 'digest'
require 'uri'
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

  get '/:code.pdf' do
    stop_code = params['code']
    halt 404 unless STOP_CODE.match?(stop_code)

    overrides = ROUTE_PARAMS.each_with_object({}) do |name, h|
      # Rack can hand the value back tagged binary, and [[:alnum:]] only knows
      # about Cyrillic route names on a UTF-8 string.
      value = params[name].to_s.dup.force_encoding(Encoding::UTF_8)
      next if value.empty?
      halt 400, "Bad #{name} parameter" unless value.valid_encoding? && ROUTE_LIST.match?(value)

      h[name] = value
    end

    url = "https://offline.lad.lviv.ua/#{stop_code}"
    url += "?#{URI.encode_www_form(overrides)}" if overrides.any?

    # The overrides change what is drawn, so they have to change the cache path
    # too, or one route set is served under another's name.
    file_path = "/tmp/#{stop_code}-#{Digest::SHA256.hexdigest(url)[0, 16]}.pdf"

    # Argument list, not a command string: no shell, nothing to quote-escape.
    ok = system('wkhtmltopdf', '-q',
                '--page-height', '310mm', '--page-width', '460mm',
                '-B', '0', '-L', '0', '-R', '0', '-T', '0',
                '--zoom', '0.35', '--disable-external-links',
                url, file_path)

    halt 502, 'Не вдалося згенерувати PDF' unless ok && File.exist?(file_path)

    content_type 'application/pdf'
    send_file(file_path, :disposition => 'attachment', :filename => "#{stop_code}.pdf")
  end

end

App.run!