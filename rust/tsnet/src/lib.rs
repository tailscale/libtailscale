use bindings::{TailscaleBinding, TailscaleConnBinding, TailscaleListenerBinding};
use std::ffi::{CStr, CString, c_char};

/// Raw bindings for libtailscale
mod bindings {
    include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
}

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
type TailscaleListener = i32;

/// A TailscaleConnection is a connection to an address on the tailnet.
///
/// It is a pipe(2) on which you can use read(2), write(2), and close(2).
pub type TailscaleConnection = i32;

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

fn tailscale_error_msg(server: TailscaleBinding) -> Result<String, String> {
    let mut buffer = vec![0u8; 2048];
    let result = unsafe {
        bindings::tailscale_errmsg(server, buffer.as_mut_ptr() as *mut c_char, buffer.len())
    };

    if result != 0 {
        return Err(tailscale_error_msg(server)?);
    }

    let message = unsafe { CStr::from_ptr(buffer.as_ptr() as *const c_char) };
    Ok(message.to_str().unwrap().to_string())
}
