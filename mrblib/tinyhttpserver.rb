module ESP32
  class TinyHttpServer
    RECV_BUF     = 1024

    def initialize(opt)
      @config = {}
      @document_root = opt[:DocumentRoot]
      @host = "0.0.0.0"
      @port = opt[:Port]
      @timeout = 0
      @nonblock = false
      @parser = HTTP::Parser.new()
      @proc_list = {}
    end

    def run
      puts "start TCP server"
      tcp = TCPServer.new(@host, @port)

      loop do
        io = accept_connection(tcp)
        puts "Accept connection"
  
        begin
          data = receive_data(io)
          puts data
          send_data(io, handle_data(io, data)) if data != nil
          puts "send_data done"
        rescue => e
          puts "Exception!"
          puts e
          raise 'Connection reset by peer' if @config[:debug] && io.closed?
        ensure
          io.close rescue nil
          GC.start if @config[:run_gc_per_request]
        end
      end
    end

    def handle_data(io, data)
      puts "handle_data"
      req = {}
      @parser.parse_request(data) do |x|
        req[:method] = x.method
        req[:schema] = x.schema
        req[:host] = x.host
        req[:port] = x.port
        req[:path] = x.path
        puts x.query
        q = {}

        req[:query] = q
      end
      puts "req path:#{req[:path]}"
      res = {}
      res[:code] = 200
      res[:ctype] = "text/html" #'application/octet-stream'
      res[:connection] = "close"
      res[:body] = ""
      if @proc_list[req[:path]]
        puts "call proc"
        @proc_list[req[:path]].call(req,res)
      else
        puts "error"
        res[:code] = 404
      end
      data = make_msg(res)
      puts data
      data
    end

    def make_msg(res)
      case res[:code]
      when 200
        size = res[:body].bytesize
        header = "HTTP/1.1 200 OK\r\nConnection: #{res[:cc]}\r\nContent-Type: #{res[:ctype]}\r\nContent-Length: #{size}\r\n\r\n"
        return header+res[:body]
      when 500
        return "HTTP/1.0 500 Internal Server Error\r\n\r\n500 Internal Server Error"
      when 404
        return "HTTP/1.0 404 Not Found\r\n\r\n404 Not Found"
      end
      "HTTP/1.0 500 Internal Server Error\r\n\r\n500 Internal Server Error"
    end

    def send_data(io, data)
      puts "send_data"
      loop do
        n = io.syswrite(data)
        return if n == data.bytesize
        data = data[n..-1]
      end
    end

    def accept_connection(tcp)
      counter = counter ? counter + 1 : 1
  
      sock = BasicSocket.for_fd(tcp.sysaccept)
      sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_NOSIGPIPE, true) if Socket.const_defined? :SO_NOSIGPIPE
      sock
    rescue RuntimeError => e
      counter == 1 ? retry : raise(e)
    end

    def receive_data(io)
      data = nil
      time = Time.now if @nonblock
      ext  = String.method_defined? :<<
  
      loop do
        begin
          buf = io.recv(RECV_BUF, @nonblock ? Socket::MSG_DONTWAIT : 0)
  
          if !data
            data = buf
          elsif ext
            data << buf
          else
            data += buf
          end
  
          return data if buf.size != RECV_BUF
        rescue
          next if (Time.now - time) < @timeout
        end
      end
    end

    def mount(path,file_path)
      proc = Proc.new do |req,res|
        #load file
        puts "req_path : #{req[:path]}"
        puts "file_path: #{file_path}"
        
        ESP32::File.open(file_path,"r") do |fd|
          puts "Open OK"
          res[:body] = fd.read
        end
      end
      puts "mount (#{path})"
      @proc_list[path] = proc
    end

    def mount_proc(path,&block)
      puts "mount (#{path})"
      @proc_list[path] = block
    end

    def umount(path)
      @proc_list[path] = nil
    end

  end
end