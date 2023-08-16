extern crate bindgen;

use std::env;
use std::path::PathBuf;
        use std::process::Command;

fn main() {
    #[allow(unused_assignments)]
    let mut header_location = "../../tailscale.h";
    
    // if we bundled libtailscale sources, then build them
    #[cfg(feature = "bundled")]
    {
        // TODO(Xe): extract the bundled tarball once #8 lands
        #[cfg(debug_assertions)]
        println!(
            "cargo:warning=go build started: {}/libtailscale.a",
            env::var("OUT_DIR").unwrap()
        );
        Command::new("go") // TODO(Xe): change curdir to extracted tarball location
            .arg("build")
            .arg("-buildmode=c-archive")
            .arg("-o")
            .arg(&format!("{}/libtailscale.a", env::var("OUT_DIR").unwrap()))
            .arg("../..") // TODO(Xe): change location to extracted tarball location
            .spawn()
            .expect("go build -buildmode=c-archive to work")
            .wait()
            .expect("go build -buildmode=c-archive to complete successfully");
        #[cfg(debug_assertions)]
        println!("cargo:warning=go build finished");
        
        // add this to the LDPATH
        println!("cargo:rustc-link-search={}", env::var("OUT_DIR").unwrap());

        // point header to extracted tarball
        header_location = "../../tailscale.h"; // TODO(Xe): change location to extracted tarball
    }

    // for local development
    #[cfg(not(feature = "bundled"))]
    {
        Command::new("go")
            .arg("build")
            .arg("-buildmode=c-archive")
            .arg("-o")
            .arg(&format!("{}/libtailscale.a", env::var("OUT_DIR").unwrap()))
            .arg("../..")
            .spawn()
            .expect("go build -buildmode=c-archive to work")
            .wait()
            .expect("go build -buildmode=c-archive to complete successfully");
        // add this to the LDPATH
        println!("cargo:rustc-link-search={}", env::var("OUT_DIR").unwrap());
    }

    // Tell cargo to invalidate the built crate whenever the wrapper changes
    println!("cargo:rerun-if-changed={header_location}");
    
    // Tell cargo to tell rustc to link the built libtailscale
    // static library.
    println!("cargo:rustc-link-lib=tailscale");

    // on macOS, link CoreFoundation and Security
    #[cfg(target_os = "macos")]
    {
        println!("cargo:rustc-flags=-l framework=CoreFoundation -l framework=Security");
    }

    // The bindgen::Builder is the main entry point
    // to bindgen, and lets you build up options for
    // the resulting bindings.
    let bindings = bindgen::Builder::default()
        // The input header we would like to generate
        // bindings for.
        .header(header_location)
        // Tell cargo to invalidate the built crate whenever any of the
        // included header files changed.
        .parse_callbacks(Box::new(bindgen::CargoCallbacks))
        // Finish the builder and generate the bindings.
        .generate()
        // Unwrap the Result and panic on failure.
        .expect("Unable to generate bindings");

    // Write the bindings to the $OUT_DIR/bindings.rs file.
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
