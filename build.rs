fn main() {
    println!("cargo:rustc-link-search=.");
    println!("cargo:rustc-link-lib=static=tailscale");
    println!("cargo:rustc-link-lib=framework=CoreFoundation");
    println!("cargo:rustc-link-lib=framework=IOKit");
    println!("cargo:rustc-link-lib=framework=Security");
}
