import http.server, os
os.chdir('/Users/tanaree/Documents/robo-cup-2')
http.server.test(HandlerClass=http.server.SimpleHTTPRequestHandler, port=3000, bind='')
