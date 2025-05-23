use bindings::{TailscaleBinding, TailscaleConnBinding, TailscaleListenerBinding};

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
