require 'sinatra/base'

class App < Sinatra::Base

  get '/:code.pdf' do
    stop_code = params['code']
    url = "https://offline.lad.lviv.ua/#{stop_code}"
    file_path = "/tmp/#{stop_code}.pdf"

    result = system("wkhtmltopdf -q --page-height 350mm --page-width 500mm -B 0 -L 0 -R 0 -T 0 --zoom 0.5 --disable-external-links '#{url}' '#{file_path}'")

    content_type 'application/pdf'
    io = StringIO.new(file_path)
    send_file(io.string, :disposition => 'attachment', :filename => "#{stop_code}.pdf")
  end

end

App.run!