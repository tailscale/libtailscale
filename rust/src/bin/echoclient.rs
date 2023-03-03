use tsnet::Server;
use std::{io::Write, env};

fn main() {
    let target = env::args().skip(1).next().unwrap();
    let srv = Server::new()
        .hostname("tsnet-rs-echoclient")
        .ephemeral()
        .authkey(env::var("TS_AUTHKEY").unwrap())
        .build()
        .unwrap();

    let mut conn = srv.dial("tcp", &target).unwrap();
    write!(conn, "This is a test of the Tailscale connection service.\n").unwrap();
}
