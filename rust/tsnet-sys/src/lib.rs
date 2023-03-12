#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_and_close() {
        let srv = unsafe { tailscale_new() };
        assert_eq!(unsafe { tailscale_start(srv) }, 0);
        assert_eq!(unsafe { tailscale_close(srv) }, 0);
        drop(srv);
    }
}
