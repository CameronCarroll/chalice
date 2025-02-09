# Chalice Test Client
# Purpose: Sends a URI request to server and prints out the response.
# Warning - For local testing only - skips and can't handle SSL cert verification.
# by ieve, January 2025

require "socket"
require "openssl"

CRLF = "\r\n"

#request2 = "gemini://localhost/subfolder/subfolder2/document.gmi"
#request2 = "gemini://localhost/test.');\"%bf%5c%27--gmi;\"\\\".gemini"
# request2 = "gemini://domain.net/subfolder/subfolder2/document.gmi"
#request2 = "gemini://localhost/test.gmi"
# request2 = "gemini://localhost\\..\secret.gmi"
# request2 = "gemini:/domain.net"
# request2 = "http://foo.com/posts?id=30&limit=5#t\#{puts}ime=1305298413"
# request2 = "gemini://ieve:hunter2@localhost"
# request2 = "gemini://localhost/../../../etc/passwd"
# request2 = "gemini://localhost/..\etc/passwd"
# request2 = "gemini://localhost/./etc/passwd"
#request2 = "geminingjsfngfios5408954gemini://"
request2 = nil
#request2 = ""

request = request2 || ARGF.gets_to_end

TCPSocket.open("localhost", 1965) do |socket|
  context = OpenSSL::SSL::Context::Client.new
  # Note that this skips SSL certificate verification:
  #context.verify_mode = OpenSSL::SSL::VerifyMode::NONE

  OpenSSL::SSL::Socket::Client.open(socket, context) do |ssl_socket|
    ssl_socket.sync_close = true
    puts "--------------------" + CRLF + CRLF
    puts "Sending request: #{request.inspect}"
    puts "Request is #{request.bytesize} bytes"
    ssl_socket.puts request + CRLF
    ssl_socket.flush
    header = ssl_socket.gets
    content = ssl_socket.gets_to_end

    if header.nil?
      puts "No response received. Something went wrong."
    else
      puts "Header received: #{header.inspect}"
      puts "Content received: #{content.inspect}"
    end
  end
end
