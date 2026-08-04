require 'sinatra/base'
require 'rackup'
# Load thin fully before Rackup resolves its handler; the handler file alone
# does not pull in Thin::Logging (thin 2.0.1).
require 'thin'

class App < Sinatra::Base

  set :server, 'thin'
  set :bind, '0.0.0.0'

  # The stop code reaches a subprocess argument and a file path, so keep it to
  # characters that can mean nothing in either.
  STOP_CODE = /\A[A-Za-z0-9_-]{1,32}\z/.freeze

  get '/:code.pdf' do
    stop_code = params['code']
    halt 404 unless STOP_CODE.match?(stop_code)

    url = "https://offline.lad.lviv.ua/#{stop_code}"
    file_path = "/tmp/#{stop_code}.pdf"

    # Argument list, not a command string: no shell, nothing to quote-escape.
    system('wkhtmltopdf', '-q',
           '--page-height', '310mm', '--page-width', '460mm',
           '-B', '0', '-L', '0', '-R', '0', '-T', '0',
           '--zoom', '0.35', '--disable-external-links',
           url, file_path)

    content_type 'application/pdf'
    send_file(file_path, :disposition => 'attachment', :filename => "#{stop_code}.pdf")
  end

end

App.run!