use std::env;
use tokio::io::AsyncWriteExt;
use tokio::runtime::Builder;
use tsnet::Server;

fn main() {
    let target = env::args()
        .skip(1)
        .next()
        .expect("usage: echoclient_async <host:port>");
    let srv = Server::new()
        .hostname("tsnet-rs-echoclient-async")
        .ephemeral()
        .authkey(env::var("TS_AUTHKEY").expect("want TS_AUTHKEY in environment"))
        .build()
        .unwrap();

        let rt = Builder::new_current_thread().enable_all().build().unwrap();
        rt.block_on(async {
            let mut conn = srv.dial_async("tcp", &target).unwrap();
            conn.write_all(b"Hi from async connection land!\n").await.unwrap();
        });
}
