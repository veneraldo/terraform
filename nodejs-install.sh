yum install -y gcc-c++ make 
curl -sL https://rpm.nodesource.com/setup_14.x | sudo -E bash -
yum install -y nodejs 

cat > demo_server.js<< EOF
var http = require('http');
http.createServer(function (req, res) {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end('Welcome Node.js');
}).listen(3000, "127.0.0.1");
console.log('Server running at http://127.0.0.1:3000/');
EOF
node --inspect demo_server.js 