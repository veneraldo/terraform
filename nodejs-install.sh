#!/bin/bash
apt update -y
apt install nodejs -y
cat > demo_server.js<< EOF
const http = require("http");
const server = http.createServer((req, res) => {
  const urlPath = req.url;
  if (urlPath === "/overview") {
    res.end('Welcome to the "overview page" of the node project');
    } else if (urlPath === "/api") {
     res.writeHead(200, { "Content-Type": "application/json" });
     res.end(
      JSON.stringify({
       product_id: "xyz12u3",
       product_name: "test api",
	            })
			    );
      } else {
         res.end("Successfully started a nodejs server");
        }
});
server.listen(80, "0.0.0.0", () => {
	  console.log("Listening for request");
});
EOF
node --inspect demo_server.js & 