use tsnet::Server;
use std::{io::{Write, Read}, env, thread, net::TcpStream};

fn main() {
    let hostport = env::args().skip(1).next().unwrap();
    let srv = Server::new()
        .hostname("tsnet-rs-echoserver")
        .ephemeral()
        .authkey(env::var("TS_AUTHKEY").unwrap())
        .build()
        .unwrap();

    let mut ln = srv.listen("tcp", &hostport).unwrap();
    loop {
        let conn = ln.accept().unwrap();

        thread::spawn(move ||{
            handle_client(conn);
        });
    }
}

fn handle_client(mut stream: TcpStream) {
    // read 20 bytes at a time from stream echoing back to stream
    loop {
        let mut read = [0; 1028];
        match stream.read(&mut read) {
            Ok(n) => {
                if n == 0 { 
                    // connection was closed
                    break;
                }
                stream.write(&read[0..n]).unwrap();
            }
            Err(err) => {
                panic!("{err}");
            }
        }
    }
}
