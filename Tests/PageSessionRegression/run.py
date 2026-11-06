"""Run the WKWebView checks with a real, loopback-only HTTP error response."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os,subprocess,sys,threading
class ErrorPage(BaseHTTPRequestHandler):
    def do_GET(self):
        data=b'<html><body>400 test error</body></html>'
        self.send_response(400)
        self.send_header('Content-Type','text/html')
        self.send_header('Content-Length',str(len(data)))
        self.end_headers();self.wfile.write(data)
    def log_message(self,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',0),ErrorPage)
threading.Thread(target=server.serve_forever,daemon=True).start()
env=os.environ.copy();env['QINGYI_TEST_HTTP_URL']=f'http://127.0.0.1:{server.server_port}/error'
try: result=subprocess.run([sys.argv[1]],env=env,timeout=120)
finally: server.shutdown();server.server_close()
sys.exit(result.returncode)
