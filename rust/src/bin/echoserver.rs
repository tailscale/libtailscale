use std::{
    env,
    io::{Read, Write},
    net::TcpStream,
    thread,
};
use tsnet::Server;

fn main() {
    let hostport = env::args().skip(1).next().expect("usage: echoserver host:port");
    let srv = Server::new()
        .hostname("tsnet-rs-echoserver")
        .ephemeral()
        .authkey(env::var("TS_AUTHKEY").expect("set TS_AUTHKEY in environment"))
        .build()
        .unwrap();

    let ln = srv.listen("tcp", &hostport).unwrap();
    for conn in ln {
        match conn {
            Ok(conn) => {
                match conn.peer_addr() {
                    Ok(addr) => println!("remote IP: {addr}"),
                    Err(err) => eprintln!("can't read remote IP: {err}"),
                }

                thread::spawn(move || {
                    handle_client(conn);
                });
            }
            Err(err) => panic!("{err}"),
        }
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
