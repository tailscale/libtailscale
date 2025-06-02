use bindings::{TailscaleBinding, TailscaleConnBinding, TailscaleListenerBinding};
use std::{
    ffi::{c_char, CStr, CString},
    os::fd::{AsFd, AsRawFd, BorrowedFd, FromRawFd, OwnedFd},
};

/// Raw bindings for libtailscale
mod bindings {
    include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
}

const ERANGE: i32 = 34;
const EBADF: i32 = 9;
const INET6_ADDRSTRLEN: usize = 46;

/// A TailscaleListener is a socket on the tailnet listening for connections.
///
/// It is much like allocating a system socket(2) and calling listen(2).
/// Accept connections with tailscale_accept and close the listener  with close.
///
/// Under the hood, a tailscale_listener is one half of a socketpair itself,
/// used to move the connection fd from Go to C. This means you can use epoll
/// or its equivalent on a tailscale_listener to know if there is a connection
/// read to accept.
// Define TailscaleListenerBinding based on platform
pub type TailscaleListener = OwnedFd;

/// A TailscaleConnection is a connection to an address on the tailnet.
///
/// It is a pipe(2) on which you can use read(2), write(2), and close(2).
pub type TailscaleConnection = OwnedFd;

/// Represents a Tailscale server instance
pub struct TSNet {
    server: TailscaleBinding,
}

/// Optional parameters that, if needed,
/// must be set before any explicit or implicit call to tailscale_start.
pub struct Config {
    dir: Option<String>,
    hostname: Option<String>,
    authkey: Option<String>,
    control_url: Option<String>,
    ephemeral: bool,
    logging_fd: i32,
}

/// A convenience builder to help create a new TSNet instance.
///
/// ```
/// let config = tailscale::ConfigBuilder::new()
/// .dir(state_dir)
/// .ephemeral(true)
/// .hostname("rust-example")
/// .build()?;
///
/// let mut ts = TSNet::new(config)?;
/// ```
pub struct ConfigBuilder {
    dir: Option<String>,
    hostname: Option<String>,
    authkey: Option<String>,
    control_url: Option<String>,
    ephemeral: bool,
    logging_fd: i32,
}

impl ConfigBuilder {
    pub fn new() -> Self {
        ConfigBuilder {
            dir: None,
            hostname: None,
            authkey: None,
            control_url: None,
            ephemeral: false,
            logging_fd: -1,
        }
    }

    pub fn dir(mut self, dir: &str) -> Self {
        self.dir = Some(dir.to_string());
        self
    }

    pub fn hostname(mut self, hostname: &str) -> Self {
        self.hostname = Some(hostname.to_string());
        self
    }

    pub fn authkey(mut self, authkey: &str) -> Self {
        self.authkey = Some(authkey.to_string());
        self
    }

    pub fn control_url(mut self, control_url: &str) -> Self {
        self.control_url = Some(control_url.to_string());
        self
    }

    pub fn ephemeral(mut self, ephemeral: bool) -> Self {
        self.ephemeral = ephemeral;
        self
    }

    pub fn logging_fd(mut self, logging_fd: i32) -> Self {
        self.logging_fd = logging_fd;
        self
    }

    pub fn build(self) -> Result<Config, String> {
        Ok(Config {
            dir: self.dir,
            hostname: self.hostname,
            authkey: self.authkey,
            control_url: self.control_url,
            ephemeral: self.ephemeral,
            logging_fd: self.logging_fd,
        })
    }
}

impl TSNet {
    /// Creates a new Tailscale server instance
    ///
    /// No network connection is initialized until start is called.
    pub fn new(config: Config) -> Result<Self, String> {
        let server = unsafe { bindings::tailscale_new() };

        if let Some(authkey) = config.authkey {
            set_auth_key(server, &authkey)?;
        }

        if let Some(dir) = config.dir {
            set_dir(server, &dir)?;
        }

        if let Some(hostname) = config.hostname {
            set_hostname(server, &hostname)?;
        }

        if let Some(control_url) = config.control_url {
            set_control_url(server, &control_url)?;
        }

        if config.ephemeral {
            set_ephemeral(server, config.ephemeral)?;
        }

        set_log_fd(server, config.logging_fd)?;

        Ok(Self { server })
    }

    /// Connects the server to the tailnet and waits for it to be usable.
    /// To cancel an in-progress call to up, use `close`.
    pub fn up(&mut self) -> Result<(), String> {
        let result = unsafe { bindings::tailscale_up(self.server) };

        if result != 0 {
            Err(tailscale_error_msg(self.server)?)
        } else {
            Ok(())
        }
    }

    /// Shuts down the server.
    /// The server is automatically closed when the TSNet instance is dropped.
    /// This method is provided for completeness.
    pub fn close(&mut self) -> Result<(), String> {
        let result = unsafe { bindings::tailscale_close(self.server) };

        if result != 0 {
            Err(tailscale_error_msg(self.server)?)
        } else {
            Ok(())
        }
    }

    /// Connects the server to the tailnet.
    /// Calling this function is optional as it will be called by the first use
    /// of listen or dial on a server.
    ///
    /// See also `up`
    pub fn start(&mut self) -> Result<(), String> {
        let result = unsafe { bindings::tailscale_start(self.server) };

        if result != 0 {
            Err(tailscale_error_msg(self.server)?)
        } else {
            Ok(())
        }
    }

    /// Returns the IP addresses of the the Tailscale server as
    /// a comma separated list.
    ///
    /// The provided buffer must be of sufficient size to hold the concatenated
    /// IPs as strings.  This is typically <ipv4>,<ipv6> but maybe empty, or
    /// contain any number of ips.   The caller is responsible for parsing
    /// the output.  You may assume the output is a list of well-formed IPs.
    pub fn get_ips(&self, ip_buffer_size: Option<usize>) -> Result<String, String> {
        let buffer_size = ip_buffer_size.unwrap_or(2048);
        let mut buffer = vec![0u8; buffer_size];

        let result = unsafe {
            bindings::tailscale_getips(self.server, buffer.as_mut_ptr() as *mut c_char, buffer_size)
        };

        if result == EBADF || result == ERANGE {
            return Err(tailscale_error_msg(self.server)?);
        }

        let c_str = unsafe { CStr::from_ptr(buffer.as_ptr() as *const c_char) };
        let ip_string = c_str
            .to_str()
            .map_err(|e| format!("Invalid UTF-8 in IP string: {}", e))?
            .to_string();

        Ok(ip_string)
    }

    /// Listens for a connection on the tailnet.
    ///
    /// It is the spiritual equivalent to listen(2).
    /// Returns the newly allocated listener.
    ///
    /// network is a string of the form "tcp", "udp", etc.
    /// addr is a string of an IP address or domain name.
    ///
    /// Calls `start` if the server has not yet been started.
    ///
    /// Listen on a specific interface
    /// ```
    /// let mut ts = TSNet::new(config)?;
    /// ts.listen("tcp", "127.0.0.1:8080")?;
    /// ```
    /// Listen on all interfaces
    /// ```
    /// let mut ts = TSNet::new(config)?;
    /// ts.listen("tcp", ":8080")?;
    /// ```
    pub fn listen(&self, network: &str, addr: &str) -> Result<TailscaleListener, String> {
        let server = self.server;
        let network = CString::new(network).map_err(|e| e.to_string())?;
        let addr = CString::new(addr).map_err(|e| e.to_string())?;
        let mut listener_out: TailscaleListenerBinding = -1;

        let result = unsafe {
            bindings::tailscale_listen(server, network.as_ptr(), addr.as_ptr(), &mut listener_out)
        };

        if result != 0 {
            return Err(tailscale_error_msg(server)?);
        }

        Ok(unsafe { OwnedFd::from_raw_fd(listener_out) })
    }

    /// tailscale_accept accepts a connection on a tailscale_listener.
    ///
    /// It is the spiritual equivalent to accept(2).
    ///
    /// The newly allocated connection is written to conn_out.
    pub fn accept(&self, listener: BorrowedFd) -> Result<TailscaleConnection, String> {
        let mut conn_out: i32 = -1;
        let result = unsafe { bindings::tailscale_accept(listener.as_raw_fd(), &mut conn_out) };

        if result != 0 {
            return Err(tailscale_error_msg(self.server)?);
        }

        Ok(unsafe { OwnedFd::from_raw_fd(conn_out) })
    }

    /// Connects to the address on the tailnet.
    ///
    /// network is a string of the form "tcp", "udp", etc.
    /// addr is a string of an IP address or domain name.
    ///
    /// It will start the server if it has not been started yet.
    pub fn dial(&self, network: &str, addr: &str) -> Result<TailscaleConnection, String> {
        let network = CString::new(network).map_err(|e| e.to_string())?;
        let addr = CString::new(addr).map_err(|e| e.to_string())?;
        let mut conn_out: TailscaleConnBinding = -1;
        let result = unsafe {
            bindings::tailscale_dial(self.server, network.as_ptr(), addr.as_ptr(), &mut conn_out)
        };
        if result != 0 {
            return Err(tailscale_error_msg(self.server)?);
        }
        Ok(unsafe { OwnedFd::from_raw_fd(conn_out) })
    }

    /// Returns the remote address (either ip4 or ip6)
    /// for an incoming connection for a particular listener.
    /// ```
    /// let listener = ts.listen("tcp", ":1999")?;
    /// let (conn, mut stream) = ts.accept(listener).unwrap();
    /// let remote_addr = ts.get_remote_addr(conn, listener).unwrap();
    /// ```
    pub fn get_remote_addr(
        &self,
        conn: BorrowedFd,
        listener: BorrowedFd,
    ) -> Result<String, String> {
        let server = self.server;
        let mut addr_out: [c_char; INET6_ADDRSTRLEN] = [0; INET6_ADDRSTRLEN];
        let fd = conn.as_fd();
        let result = unsafe {
            bindings::tailscale_getremoteaddr(
                listener.as_raw_fd(),
                fd.as_raw_fd(),
                addr_out.as_mut_ptr(),
                addr_out.len(),
            )
        };
        if result != 0 {
            return Err(tailscale_error_msg(server)?);
        }

        let c_str = unsafe { CStr::from_ptr(addr_out.as_ptr() as *const c_char) };
        let addr_string = c_str
            .to_str()
            .map_err(|e| format!("Invalid UTF-8 in IP string: {}", e))?
            .to_string();
        Ok(addr_string)
    }

    /// Starts a loopback address server.
    ///
    /// The server has multiple functions.
    ///
    /// It can be used as a SOCKS5 proxy onto the tailnet.
    /// Authentication is required with the username "tsnet" and
    /// the value of proxy_cred used as the password.
    ///
    /// The HTTP server also serves out the "LocalAPI" on /localapi.
    /// As the LocalAPI is powerful, access to endpoints requires BOTH passing a
    /// "Sec-Tailscale: localapi" HTTP header and passing local_api_cred as
    /// the basic auth password.
    ///
    /// The pointers proxy_cred_out and local_api_cred_out must be non-NIL
    /// and point to arrays that can hold 33 bytes. The first 32 bytes are
    /// the credential and the final byte is a NUL terminator.
    ///
    /// If tailscale_loopback returns, then addr_our, proxy_cred_out,
    /// and local_api_cred_out are all NUL-terminated.
    ///
    /// Returns the address and credentials for the proxy and local API.
    /// (address, proxy_cred, local_api_cred)
    ///
    /// ```
    /// let (proxy_cred, local_api_cred) = ts.loopback("127.0.0.1:1999")?;
    /// ```
    pub fn loopback(&self) -> Result<(String, String, String), String> {
        let mut address_out = [0; 33];
        let mut proxy_cred_out = [0; 33];
        let mut local_api_cred_out = [0; 33];

        let result = unsafe {
            bindings::tailscale_loopback(
                self.server,
                address_out.as_mut_ptr(),
                address_out.len(),
                proxy_cred_out.as_mut_ptr(),
                local_api_cred_out.as_mut_ptr(),
            )
        };
        if result != 0 {
            return Err(tailscale_error_msg(self.server)?);
        }

        let address_out = unsafe { CStr::from_ptr(address_out.as_ptr() as *const c_char) };
        let proxy_cred_out = unsafe { CStr::from_ptr(proxy_cred_out.as_ptr() as *const c_char) };
        let local_api_cred_out =
            unsafe { CStr::from_ptr(local_api_cred_out.as_ptr() as *const c_char) };

        Ok((
            address_out.to_string_lossy().into_owned(),
            proxy_cred_out.to_string_lossy().into_owned(),
            local_api_cred_out.to_string_lossy().into_owned(),
        ))
    }

    /// Configures the server to have Tailscale Funnel enabled,
    /// routing requests from the public web
    /// (without any authentication) down to this Tailscale node, requesting new
    /// LetsEncrypt TLS certs as needed, terminating TLS, and proxying all incoming
    /// HTTPS requests to http:///127.0.0.1:localhostPort without TLS.
    ///
    /// There should be a plaintext HTTP/1 server listening on 127.0.0.1:localhostPort
    /// or tsnet will serve HTTP 502 errors.
    ///
    /// Expect junk traffic from the internet from bots watching the public CT logs.
    pub fn enable_funnel_to_localhost_plaintext_http1(&self, port: i32) -> Result<(), String> {
        let result = unsafe {
            bindings::tailscale_enable_funnel_to_localhost_plaintext_http1(self.server, port)
        };
        if result != 0 {
            return Err(tailscale_error_msg(self.server)?);
        }

        Ok(())
    }
}

/// Drop the TSNet instance
impl Drop for TSNet {
    fn drop(&mut self) {
        unsafe {
            let result = bindings::tailscale_close(self.server);
            if result != 0 {
                println!("Failed to close Tailscale server: {}", result);
            }
        }
    }
}

/// This setting lets you set an auth key so that your program will automatically authenticate
/// with the Tailscale control plane. By default it pulls from the environment variable TS_AUTHKEY,
/// but you can set your own logic like this:
/// ```
/// let config = tailscale::ConfigBuilder::new()
/// .authkey(&key)
/// .build()?;
///
/// let mut ts = TSNet::new(config)?;
/// ```
///
fn set_auth_key(server: TailscaleBinding, key: &str) -> Result<(), String> {
    let key_cstr = CString::new(key).map_err(|e| e.to_string())?;
    let result = unsafe { bindings::tailscale_set_authkey(server, key_cstr.as_ptr()) };
    if result != 0 {
        return Err(tailscale_error_msg(server)?);
    }
    Ok(())
}

/// This setting lets you control the directory that the tsnet.Server stores data in persistently.
/// By default,tsnet will store data in your user configuration directory based on the name of the binary.
/// Note that this folder must already exist or tsnet calls will fail.
/// Here is how to override this to store data in /data/tsnet:
/// ```
/// let config = tailscale::ConfigBuilder::new()
/// .dir("/data/tsnet")
/// .build()?;
///
/// let mut ts = TSNet::new(config)?;
/// ```
///
fn set_dir(server: TailscaleBinding, dir: &str) -> Result<(), String> {
    let dir_cstr = CString::new(dir).map_err(|e| e.to_string())?;
    let result = unsafe { bindings::tailscale_set_dir(server, dir_cstr.as_ptr()) };
    if result != 0 {
        return Err(tailscale_error_msg(server)?);
    }
    Ok(())
}

/// This setting lets you control the host name of your program in your tailnet.
/// By default, this will be the name of your program,
/// such as foo for a program stored at /usr/local/bin/foo.
/// You can also override this by setting the Hostname field:
/// ```
/// let config = tailscale::ConfigBuilder::new()
/// .hostname("rust-example")
/// .build()?;
///
/// let mut ts = TSNet::new(config)?;
/// ```
///
fn set_hostname(server: TailscaleBinding, hostname: &str) -> Result<(), String> {
    let hostname_cstr = CString::new(hostname).map_err(|e| e.to_string())?;
    let result = unsafe { bindings::tailscale_set_hostname(server, hostname_cstr.as_ptr()) };
    if result != 0 {
        return Err(tailscale_error_msg(server)?);
    }
    Ok(())
}

/// This setting lets you control whether the node should be registered as an ephemeral node.
/// Ephemeral nodes are automatically cleaned up after they disconnect from the control plane.
/// This is useful when using tsnet in serverless environments or when facts
/// and circumstances forbid you from using persistent state.
/// ```
/// let config = tailscale::ConfigBuilder::new()
/// .ephemeral(true)
/// .build()?;
///
/// let mut ts = TSNet::new(config)?;
/// ```
///
fn set_ephemeral(server: TailscaleBinding, ephemeral: bool) -> Result<(), String> {
    let result = unsafe { bindings::tailscale_set_ephemeral(server, ephemeral as i32) };
    if result != 0 {
        return Err(tailscale_error_msg(server)?);
    }
    Ok(())
}
/// This setting specifies the coordination server URL.
/// If empty, the Tailscale default is used.
/// ```
/// let config = tailscale::ConfigBuilder::new()
/// .control_url("https://controlplane.tailscale.com")
/// .build()?;
///
/// let mut ts = TSNet::new(config)?;
/// ```
///
fn set_control_url(server: TailscaleBinding, control_url: &str) -> Result<(), String> {
    let control_url_cstr = CString::new(control_url).map_err(|e| e.to_string())?;
    let result = unsafe { bindings::tailscale_set_control_url(server, control_url_cstr.as_ptr()) };
    if result != 0 {
        return Err(tailscale_error_msg(server)?);
    }
    Ok(())
}

/// Instructs the tailscale instance to write logs to fd.
///
/// An fd value of -1 means discard all logging.
/// ```
/// let config = tailscale::ConfigBuilder::new()
/// .logging_fd(-1)
/// .build()?;
///
/// let mut ts = TSNet::new(config)?;
/// ```
///
fn set_log_fd(server: TailscaleBinding, fd: i32) -> Result<(), String> {
    let result = unsafe { bindings::tailscale_set_logfd(server, fd) };
    if result != 0 {
        return Err(tailscale_error_msg(server)?);
    }
    Ok(())
}

/// Get the last error message from the tailscale instance
fn tailscale_error_msg(server: TailscaleBinding) -> Result<String, String> {
    let mut buffer = vec![0u8; 2048];
    let result = unsafe {
        bindings::tailscale_errmsg(server, buffer.as_mut_ptr() as *mut c_char, buffer.len())
    };

    if result != 0 {
        return Err("Unknown error".to_string());
    }

    let message = unsafe { CStr::from_ptr(buffer.as_ptr() as *const c_char) };
    Ok(message.to_str().unwrap().to_string())
}
