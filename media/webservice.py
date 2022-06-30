#!/usr/bin/env python3

import os
from http.server import BaseHTTPRequestHandler
from socketserver import TCPServer


class WebService(BaseHTTPRequestHandler):

    def do_GET(self):
        self.send_response(int(os.environ.get("GET_CODE", 200)))
        self.end_headers()
        self.wfile.write(b"Lorem Ipsum\n")

    def do_POST(self):
        self.send_response(int(os.environ.get("POST_CODE", 200)))
        self.end_headers()
        self.wfile.write(b"Lorem Ipsum\n")


if __name__ == "__main__":
    port = int(os.environ["PORT"])
    with TCPServer(("0.0.0.0", port), WebService) as httpd:
        print(f"Serving at port: {port}")
        httpd.serve_forever()
