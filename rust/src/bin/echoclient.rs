use std::{env, io::Write};
use tsnet::Server;

fn main() {
    let target = env::args()
        .skip(1)
        .next()
        .expect("usage: echoclient host:port");
    let srv = Server::new()
        .hostname("tsnet-rs-echoclient")
        .ephemeral()
        .authkey(env::var("TS_AUTHKEY").expect("set TS_AUTHKEY in environment"))
        .build()
        .unwrap();

    let mut conn = srv.dial("tcp", &target).unwrap();
    write!(
        conn,
        "This is a test of the Tailscale connection service.\n"
    )
    .unwrap();
}
