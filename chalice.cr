# Chalice, a Gemini server
# Made from Crystal by ieve
# January 2025

# -------------------------------------------
# === User Configuration Stuff: ===
HOSTNAME = "localhost"
# -------------------------------------------

# -------------------------------------------
# === How to generate server certificate using openssl: ===
# openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -subj "/CN={hostname}"
# Use 'localhost' when testing locally
# Or 'example.com' when setting up live server
# -------------------------------------------

require "socket"
require "openssl"

CRLF = "\r\n"
SPACE = " "
GEMINI_SCHEME_NAME = "gemini"

class Error < Exception; end
class URIError < Error; end
class ConnectionError < Error; end

def handle_connection(connection)
  # requests from client are supposed to look like this:
  # <URL><CR><LF>
  # gemini://domain.net/subfolder/subfolder2/document.gmi\r\n
  request = connection.gets
  if request
    puts ""
    puts "--------- New Request #{Time.local.to_s}---------"
    puts "Received message #{request} from #{connection}"

    response = handle_message(request)
    connection.puts response
    puts "Sent response #{response} to #{connection}"
  else
    raise ConnectionError.new("Request data is nil")
    return
  end
ensure
  connection.close
end

def handle_message(message)
  # header is supposed to look like this:
  # <STATUS><SPACE><META><CR><LF>
  # Status codes are...
  # 10 (INPUT) - Tell client to provide user input
  # -- meta is prompt to user
  # -- no response body
  # 20 (SUCCESS) - Return some data
  # -- meta is a MIME media type
  # -- response body is... the body
  # 30 (REDIRECT) - Point somewhere else
  # -- meta is the new URL (absolute or relative)
  # -- no response body
  # 40 & 50 (FAILURE) - Failure
  # -- Spec gives differentiation between temporary (40) and permanent failure (50) but... meh. Not supported. Just sending 50.
  # -- meta can provide additional information on the failure
  # -- no response body
  # 60 (CLIENT CERTIFICATE REQUIRED) - Not supported

  request_data = decode_request(message)
  puts request_data.inspect
  if request_data["error_code"]?
    status = request_data["error_code"]
    meta = request_data["error_message"]
  else
    status = "20"
    meta = "text/gemini"
  end
  header = status + SPACE + meta + CRLF
  body = "test response"
  response = header + body
  return response
end


def decode_request(request)
  request_data = Hash(String, String).new

  # Step 0 - Check for stuff not allowed
  raise URIError.new("Bad URI (exceeds 1024 byte limit)") if request.to_s.bytesize > 1024

  raise URIError.new("Bad URI (contains fragment ('\#'))") if request.to_s =~ /\#/

  raise URIError.new("Bad URI (relative directory references not allowed)") if request.to_s =~ /\/\.\./

  # Step 1 - Split and check scheme
  # Incoming request looks something like this:
  # gemini://domain.net/subfolder/subfolder2/document.gmi
  # And we will split to look like this:
  # => ["gemini", "domain.net/subfolder/subfolder2/document.gmi"]
  request = request.split("://")
  raise URIError.new("Bad URI (couldn't split on '://')") unless request.size == 2

  # Check that request is for Gemini protocol
  request_data["scheme"] = request.first
  raise URIError.new("Bad URI (scheme isn't gemini)") unless request_data["scheme"] == GEMINI_SCHEME_NAME

  # Step 2 - Split and check hostname
  request_data["hostname"] = request.last.split("/", 2).first
  raise URIError.new("Bad URI (userinfo is not allowed)") if request_data["hostname"] =~ /@/
  raise URIError.new("Bad URI (Hostname doesn't match server configuration)") unless request_data["hostname"] == HOSTNAME


  # Step 3 - Grab the request path
  request_data["requested_path"] = request.last.split("/", 2).last
  # If there is no path and no ending slash passed in, eg "gemini://example.com", then the path and hostname end up being the same thing. In this case, manually set the requested path at root (blank string).
  # (My crude approach to normalization.)
  if request_data["requested_path"] == request_data["hostname"]
    request_data["requested_path"] = ""
  end

  return request_data
rescue e : URIError
  return { "error_message" => e.to_s, "error_code" => "59"}
end


tcp_server = TCPServer.new("localhost", 1965)
ssl_context = OpenSSL::SSL::Context::Server.new
ssl_context.certificate_chain = "server.crt"
ssl_context.private_key = "server.key"
ssl_server = OpenSSL::SSL::Server.new(tcp_server, ssl_context)
puts "Listening on #{tcp_server.local_address}"

while connection = ssl_server.accept?
  spawn handle_connection(connection)
end
