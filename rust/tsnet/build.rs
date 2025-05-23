use bindgen::callbacks::ParseCallbacks;
use std::env;
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug)]
struct RenameItems;

impl ParseCallbacks for RenameItems {
    fn item_name(&self, original_name: &str) -> Option<String> {
        // Hardcode known type names to rename to UpperCamelCase
        match original_name {
            "tailscale" => Some("TailscaleBinding".to_string()),
            "tailscale_conn" => Some("TailscaleConnBinding".to_string()),
            "tailscale_listener" => Some("TailscaleListenerBinding".to_string()),
            _ => None,
        }
    }
}

fn main() {
    // Path to the libtailscale submodule
    let project_root = "../../";
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());

    // Ensure the submodule is initialized and updated
    let status = Command::new("git")
        .args(&["submodule", "update", "--init", "--recursive"])
        .status()
        .expect("Failed to run git submodule update");
    if !status.success() {
        panic!("Failed to update submodules");
    }

    // Build libtailscale.a using Makefile
    let status = Command::new("make")
        .arg("c-archive")
        .current_dir(project_root)
        .status()
        .expect("Failed to execute make c-archive");
    if !status.success() {
        panic!("Failed to build libtailscale");
    }

    // Tell Cargo to link the static library and macOS frameworks
    println!("cargo:rustc-link-lib=static=tailscale");
    println!("cargo:rustc-link-search=native={}", project_root);

    // macos specific
    #[cfg(target_os = "macos")]
    {
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
        println!("cargo:rustc-link-lib=framework=Security");
        println!("cargo:rustc-link-lib=framework=IOKit");
        println!("cargo:rustc-link-arg=-mmacosx-version-min=15.4");
    }

    // Trigger rebuild if libtailscale.a changes
    println!("cargo:rerun-if-changed={}/libtailscale.a", project_root);

    // Generate bindings using bindgen
    let bindings = bindgen::Builder::default()
        .header(format!("{}/tailscale.h", project_root))
        .allowlist_function("tailscale_.*")
        .rustified_enum(".*")
        .parse_callbacks(Box::new(RenameItems))
        .generate()
        .expect("Unable to generate bindings for tailscale.h");

    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings to output directory");
}
