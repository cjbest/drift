fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        cc::Build::new()
            .file("src/coordinator.m")
            .file("src/menu.m")
            .file("src/notebook_access.m")
            .flag("-fobjc-arc")
            .flag("-fblocks")
            .compile("drift_coordinator");
        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=framework=AppKit");
        println!("cargo:rerun-if-changed=src/menu.m");
        println!("cargo:rerun-if-changed=src/coordinator.m");
        println!("cargo:rerun-if-changed=src/notebook_access.m");
    }
    tauri_build::build()
}
