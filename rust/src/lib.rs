use std::ffi::{c_int, CString};
use std::net::TcpStream;
use std::os::fd::FromRawFd;
use std::path::PathBuf;
use tsnet_sys as sys;

pub struct Server {
    srv: sys::tailscale,
}

impl Drop for Server {
    fn drop(&mut self) {
        // TODO: drop all sockets
        unsafe { sys::tailscale_close(self.srv) };
    }
}

impl Server {
    pub fn new() -> ServerBuilder {
        ServerBuilder::default()
    }

    /// internal function to grab error messages from tsnet.
    fn errmsg(&self) -> Result<String> {
        let msg: [u8; 1024] = [0; 1024];
        if unsafe { sys::tailscale_errmsg(self.srv, msg.as_ptr() as *mut i8, msg.len() as u64) }
            != 0
        {
            return Err(Error::FetchingErrorFromTSNet);
        }

        let result = String::from_utf8(msg.to_vec())?;
        let result = result.trim_end_matches('\0');

        Ok(result.to_string())
    }

    pub fn dial(&self, network: &str, addr: &str) -> Result<TcpStream> {
        let mut conn: sys::tailscale_conn = 0;
        let network = CString::new(network)?;
        let addr = CString::new(addr)?;

        if unsafe { sys::tailscale_dial(self.srv, network.as_ptr(), addr.as_ptr(), &mut conn) } != 0
        {
            return Err(Error::TSNet(self.errmsg()?));
        }

        let conn = conn as c_int;
        Ok(unsafe { TcpStream::from_raw_fd(conn) })
    }

    pub fn listen(&self, network: &str, addr: &str) -> Result<Listener> {
        let mut ln: sys::tailscale_listener = 0;
        let network = CString::new(network)?;
        let addr = CString::new(addr)?;

        if unsafe { sys::tailscale_listen(self.srv, network.as_ptr(), addr.as_ptr(), &mut ln) } != 0
        {
            return Err(Error::TSNet(self.errmsg()?));
        }

        Ok(Listener { ln })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("can't convert this from an OsString to a String, invalid unicode?")]
    CantConvertToString,

    #[error("error fetching error from tsnet")]
    FetchingErrorFromTSNet,

    #[error("[unexpected] string from tsnet has invalid UTF-8: {0}")]
    TSNetSentBadUTF8(#[from] std::string::FromUtf8Error),

    #[error("tsnet: {0}")]
    TSNet(String),

    #[error("your string has NULL in it: {0}")]
    NullInString(#[from] std::ffi::NulError),
}

pub type Result<T, E = Error> = std::result::Result<T, E>;

#[derive(Default)]
pub struct ServerBuilder {
    dir: Option<PathBuf>,
    hostname: Option<String>,
    authkey: Option<String>,
    control_url: Option<String>,
    ephemeral: bool,
}

impl ServerBuilder {
    pub fn dir(mut self, dir: PathBuf) -> Self {
        self.dir = Some(dir);
        self
    }

    pub fn hostname(mut self, hostname: &str) -> Self {
        self.hostname = Some(hostname.to_owned());
        self
    }

    pub fn authkey(mut self, authkey: String) -> Self {
        self.authkey = Some(authkey);
        self
    }

    pub fn control_url(mut self, control_url: String) -> Self {
        self.control_url = Some(control_url);
        self
    }

    pub fn ephemeral(mut self) -> Self {
        self.ephemeral = true;
        self
    }

    pub fn build(self) -> Result<Server> {
        let result = unsafe {
            Server {
                srv: sys::tailscale_new(),
            }
        };

        if let Some(dir) = self.dir {
            let dir = dir.into_os_string();
            let dir = dir.into_string().map_err(|_| Error::CantConvertToString)?;
            let dir = CString::new(dir)?;
            if unsafe { sys::tailscale_set_dir(result.srv, dir.as_ptr()) } != 0 {
                return Err(Error::TSNet(result.errmsg()?));
            }
        }

        if let Some(hostname) = self.hostname {
            let hostname = CString::new(hostname)?;
            if unsafe { sys::tailscale_set_hostname(result.srv, hostname.as_ptr()) } != 0 {
                return Err(Error::TSNet(result.errmsg()?));
            }
        }

        if let Some(authkey) = self.authkey {
            let authkey = CString::new(authkey)?;
            if unsafe { sys::tailscale_set_authkey(result.srv, authkey.as_ptr()) } != 0 {
                return Err(Error::TSNet(result.errmsg()?));
            }
        }

        if let Some(control_url) = self.control_url {
            let control_url = CString::new(control_url)?;
            if unsafe { sys::tailscale_set_control_url(result.srv, control_url.as_ptr()) } != 0 {
                return Err(Error::TSNet(result.errmsg()?));
            }
        }

        if unsafe { sys::tailscale_set_ephemeral(result.srv, if self.ephemeral { 1 } else { 0 }) }
            != 0
        {
            return Err(Error::TSNet(result.errmsg()?));
        }
        if unsafe { sys::tailscale_start(result.srv) } != 0 {
            return Err(Error::TSNet(result.errmsg()?));
        }

        Ok(result)
    }
}

pub struct Listener {
    ln: sys::tailscale_listener,
}

impl Listener {
    pub fn accept(&mut self) -> Result<TcpStream> {
        let mut conn: sys::tailscale_conn = 0;
        if unsafe { sys::tailscale_accept(self.ln, &mut conn) } != 0 {
            return Err(Error::FetchingErrorFromTSNet);
        }

        let conn = conn as c_int;
        Ok(unsafe { TcpStream::from_raw_fd(conn) })
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        unsafe { sys::tailscale_listener_close(self.ln) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[forbid(unsafe_code)]
    fn make_server() {
        Server::new()
            .hostname("xn--g28h") // 😂
            .ephemeral()
            .build()
            .unwrap();
    }
}
