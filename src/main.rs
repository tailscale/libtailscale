use std::io::Read;

use crate::tailscale::Connection;

#[allow(dead_code)]
mod sys {

    pub type TailscaleListener = libc::c_int;

    #[link(name = "tailscale")]
    unsafe extern "C" {
        pub fn TsnetNewServer() -> libc::c_int;
        pub fn TsnetStart(sd: libc::c_int) -> libc::c_int;
        pub fn TsnetUp(sd: libc::c_int) -> libc::c_int;
        pub fn TsnetClose(sd: libc::c_int) -> libc::c_int;
        pub fn TsnetGetIps(
            sd: libc::c_int,
            buf: *mut libc::c_char,
            buflen: libc::size_t,
        ) -> libc::c_int;
        pub fn TsnetErrmsg(
            sd: libc::c_int,
            buf: *mut libc::c_char,
            buflen: libc::size_t,
        ) -> libc::c_int;
        pub fn TsnetListen(
            sd: libc::c_int,
            network: *const libc::c_char,
            addr: *const libc::c_char,
            listener_out: *mut TailscaleListener,
        ) -> libc::c_int;
        pub fn TsnetGetRemoteAddr(
            listener: libc::c_int,
            conn: libc::c_int,
            buf: *mut libc::c_char,
            buflen: libc::size_t,
        ) -> libc::c_int;
        pub fn TsnetDial(
            sd: libc::c_int,
            network: libc::c_char,
            addr: libc::c_char,
            conn_out: *mut libc::c_int,
        ) -> libc::c_int;
        pub fn TsnetSetDir(sd: libc::c_int, str: *mut libc::c_char) -> libc::c_int;
        pub fn TsnetSetHostname(sd: libc::c_int, str: *mut libc::c_char) -> libc::c_int;
        pub fn TsnetSetAuthKey(sd: libc::c_int, str: *mut libc::c_char) -> libc::c_int;
        pub fn TsnetSetControlURL(sd: libc::c_int, str: *mut libc::c_char) -> libc::c_int;
        pub fn TsnetSetEphemeral(sd: libc::c_int, e: libc::c_int) -> libc::c_int;
        pub fn TsnetSetLogFD(sd: libc::c_int, fd: libc::c_int) -> libc::c_int;
        pub fn TsnetLoopback(
            sd: libc::c_int,
            addrOut: libc::c_char,
            addrLen: libc::size_t,
            proxyOut: libc::c_char,
            localOut: libc::c_char,
        ) -> libc::c_int;
        pub fn TsnetEnableFunnelToLocalhostPlaintextHttp1(
            sd: libc::c_int,
            localhost_port: libc::c_int,
        ) -> libc::c_int;
    }
}

mod tailscale {
    use std::{
        ffi::NulError,
        io::{IoSliceMut, Read},
        os::fd::{BorrowedFd, FromRawFd, RawFd},
        path::PathBuf,
    };

    use super::sys::*;

    use nix::sys::socket::{ControlMessageOwned, MsgFlags, recvmsg};
    use thiserror::Error;

    #[derive(Debug, Error)]
    pub enum TailscaleError {
        #[error("invalid utf-8 string")]
        Utf8Error(#[from] NulError),

        #[error("invalid listen address given")]
        InvalidAddress(#[from] std::io::Error),

        #[error("failed to recvmsg")]
        Recvmsg,

        #[error("with control message")]
        ControlMessage,
    }

    pub type Result<T> = std::result::Result<T, TailscaleError>;

    pub struct Tailscale {
        sd: libc::c_int,
    }

    #[derive(Default, Clone)]
    pub struct TailscaleBuilder {
        ephemeral: bool,
        hostname: Option<String>,
        dir: Option<PathBuf>,
    }

    impl TailscaleBuilder {
        pub fn build(&self) -> Result<Tailscale> {
            let sd = unsafe { TsnetNewServer() };
            // TODO: handle if sd is 0
            if let Some(_path) = &self.dir {
                todo!()
                // let ret = unsafe { TsnetSetDir(sd, dir.as_ptr() as *mut _) };
                // if ret != 0 {
                //     panic!("bad");
                // }
            };

            // TODO: set hostname

            Ok(Tailscale { sd })
        }

        pub fn ephemeral(&mut self, ephemeral: bool) -> &mut Self {
            let mut new = self;
            new.ephemeral = ephemeral;
            new
        }

        pub fn hostname(&mut self, hostname: impl Into<String>) -> &mut Self {
            let mut new = self;
            new.hostname = Some(hostname.into());
            new
        }
        pub fn dir(&mut self, dir: impl Into<PathBuf>) -> &mut Self {
            let mut new = self;
            new.dir = Some(dir.into());
            new
        }
    }

    pub struct Listener<'t> {
        ln: TailscaleListener,
        _tailscale: &'t Tailscale,
    }

    pub type TailscaleConn = libc::c_int;

    pub struct Connection {
        conn: TailscaleConn,
    }

    impl Drop for Connection {
        #[cfg(unix)]
        fn drop(&mut self) {
            eprintln!("dropping connection");
            if let Err(e) = nix::unistd::close(self.conn) {
                eprintln!("error dropping connection: {e}");
            }
        }

        #[cfg(not(unix))]
        fn drop(&mut self) {
            // TODO
        }
    }

    impl Read for Connection {
        fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
            let fd = unsafe { BorrowedFd::borrow_raw(self.conn) };
            nix::unistd::read(fd, buf)
                .map_err(|errno| std::io::Error::from_raw_os_error(errno as i32))
        }
    }

    impl<'t> Listener<'t> {
        pub fn accept(&self) -> Result<Connection> {
            let mut mbuf = [0u8; 256];
            let mut iov = [IoSliceMut::new(&mut mbuf)];
            let mut cbuf = nix::cmsg_space!(RawFd);

            let msg = recvmsg::<()>(self.ln, &mut iov, Some(&mut cbuf), MsgFlags::empty())
                .map_err(|_| TailscaleError::Recvmsg)?;

            // Extract the file descriptor from the control message
            for cmsg in msg.cmsgs().map_err(|_| TailscaleError::ControlMessage)? {
                if let ControlMessageOwned::ScmRights(fds) = cmsg
                    && let Some(&fd) = fds.first()
                {
                    return Ok(Connection { conn: fd });
                }
            }
            todo!()
        }
    }

    impl Tailscale {
        pub fn builder() -> TailscaleBuilder {
            TailscaleBuilder::default()
        }
        // pub fn new() -> Result<Self> {
        //     let dir = CString::new("/tmp")?;
        //     let sd = unsafe { TsnetNewServer() };
        //
        //     // TODO: handle if sd is 0
        //     let ret = unsafe { TsnetSetDir(sd, dir.as_ptr() as *mut _) };
        //     if ret != 0 {
        //         panic!("bad");
        //     }
        //
        //     Ok(Self { sd })
        // }

        // pub fn ephemeral() -> Result<Self> {
        //     let me = Self::new()?;
        //     let ret = unsafe { TsnetSetEphemeral(me.sd, 1) };
        //     me.handle_error(ret)?;
        //     Ok(me)
        // }

        pub fn up(&self) -> Result<()> {
            let ret = unsafe { TsnetUp(self.sd) };
            self.handle_error(ret)?;
            Ok(())
        }

        pub fn listener(
            &self,
            network: &str,
            // addr: impl ToSocketAddrs,
            addr: &str,
        ) -> Result<Listener<'_>> {
            let network = std::ffi::CString::new(network).map_err(TailscaleError::Utf8Error)?;
            let addr = std::ffi::CString::new(addr).map_err(TailscaleError::Utf8Error)?;
            // let addr = addr
            //     .to_socket_addrs()
            //     .map_err(TailscaleError::InvalidAddress)?
            //     .next()
            //     .ok_or_else(|| {
            //         TailscaleError::InvalidAddress(std::io::Error::new(
            //             std::io::ErrorKind::Other,
            //             "invalid address",
            //         ))
            //     })?;

            let mut listener: TailscaleListener = 0;

            let ret =
                unsafe { TsnetListen(self.sd, network.as_ptr(), addr.as_ptr(), &mut listener) };
            self.handle_error(ret)?;

            Ok(Listener {
                ln: listener,
                _tailscale: self,
            })
        }

        fn handle_error(&self, value: libc::c_int) -> Result<()> {
            if value > 0 {
                panic!("Up bad: {value}");
            }
            Ok(())
        }
    }

    impl Drop for Tailscale {
        fn drop(&mut self) {
            eprintln!("dropping server");
            let ret = unsafe { TsnetClose(self.sd) };
            if let Err(e) = self.handle_error(ret) {
                eprintln!("error dropping tailscale: {e}");
            }
        }
    }

    impl<'t> Drop for Listener<'t> {
        #[cfg(unix)]
        fn drop(&mut self) {
            eprintln!("dropping listener");
            if let Err(e) = nix::unistd::close(self.ln) {
                eprintln!("Error closing listener: {e}");
            }
        }

        #[cfg(not(unix))]
        fn drop(&mut self) {
            // TODO
        }
    }
}

fn handle_connection(mut conn: Connection) {
    let mut buf = [0u8; 2048];
    loop {
        let i = conn.read(&mut buf).unwrap();
        if i == 0 {
            eprintln!("connection dropped");
            break;
        }

        if let Ok(value) = std::str::from_utf8(&buf[..i]) {
            println!("{}", value.trim());
        }
    }
}

fn main() {
    use tailscale::*;

    let ts = Tailscale::builder().ephemeral(true).build().unwrap();
    ts.up().unwrap();

    let listener = ts.listener("tcp", ":1999").unwrap();

    eprintln!("listening for connections");

    loop {
        let conn = listener.accept().unwrap();
        eprintln!("got connection");
        std::thread::spawn(move || handle_connection(conn));
    }
}
