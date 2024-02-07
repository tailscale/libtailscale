var ref = require('ref-napi');
var ffi = require("ffi-napi");
const process = require('node:process');
const net = require('node:net');
const http = require('node:http');

var kernel32 = ffi.Library("kernel32", {
    'SetDllDirectoryA': ["bool", ["string"]]
})
kernel32.SetDllDirectoryA("pathToAdd");

var tailscale_listener_ptr = ref.refType(ref.types.int);
var tailscale_conn_ptr = ref.refType(ref.types.int);
var char_ptr = ref.refType(ref.types.char)

var path = require("path")

var Tailscale = ffi.Library(path.join(__dirname, 'libtailscale.dll'), {
    "TsnetNewServer": ['int', []],
    "TsnetUp": ['int', ['int']],
    "TsnetClose": ['int', ['int']],
    "TsnetSetControlURL": ['int', ['int', 'string']],
    "TsnetSetEphemeral": ['int', ['int', 'int']],
    "TsnetSetAuthKey": ['int', ['int', 'string']],
    "TsnetListen": ['int', ['int', 'string', 'string', tailscale_listener_ptr]],
    "TsnetAccept": ['int', ['int', tailscale_conn_ptr]],
    "TsnetErrmsg": ['int', ['int', char_ptr, 'int']],
});

const tailscale = Tailscale.TsnetNewServer();
Tailscale.TsnetSetAuthKey(tailscale, "<auth_key>")
Tailscale.TsnetSetControlURL(tailscale, "https://headscale.dev.ffd.scapps.io");
// Tailscale.TsnetSetEphemeral(tailscale, 1);​
// TODO ezt meg kéne csinálni, hogy SIGTERMre gracefully leálljon
process.on('exit', (code) => {
    console.log(`About to exit with code: ${code}`);
    Tailscale.TsnetClose(tailscale)
});

Tailscale.TsnetUp(tailscale);

let lnBuf = ref.alloc('int');

Tailscale.TsnetListen(tailscale, "tcp", ":1999", lnBuf);

let ln = lnBuf.deref();

function err() {
    var buffer = Buffer.alloc(2000);
    Tailscale.TsnetErrmsg(tailscale, buffer, 2000);
    var errorMessage = ref.readCString(buffer, 0);
    console.log('=====================');
    console.log(errorMessage);
    console.log('=====================');
}
console.log("Listening on :1999");

const server = http.createServer(function (req, res) {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('Hello World\n');
})

function accept() {
    let connRef = ref.alloc('int');
    Tailscale.TsnetAccept.async(ln, connRef, function (error) {
        console.log("JS - accepting")
        console.log("JS - ERROR: " + error)
        let conn = ref.deref(connRef);
        console.log("JS - conn: " + conn)
        //let socket = net.Socket({  fd: conn, readable: true, writable: true, allowHalfOpen: false });
        console.log("JS - socket: " + socket)
        server.emit('connection', socket)
        console.log("JS - emitted")
        if (error) {
            err()
        } else {
            console.log('JS - Connection established');
        }

        accept();
    });
}

accept();

(function wait() {
    setTimeout(wait, 1000);
})();