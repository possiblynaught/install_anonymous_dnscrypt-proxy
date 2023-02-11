# dnscrypt-proxy config generator

Script to install dnscrypt-proxy 2 on linux targets from latest release, uses randomized Anonymous DNS and Oblivious DNS over HTTPS config by default.
# TODO: FINISH targets

## INFO

This script will:
1. Check for Linux target architecture
2. Detect target architecture
3. Check for existing dnscrypt-proxy
4. Download dnscrypt-proxy 2 tarball
5. Build + install (statically linked) minisign if not installed and verify tarball with minisig. Skip this step by uncommenting ***SKIP_VERIFY=1***
6. Generate the dnscrypt-proxy.toml config with Anonymous DNS + ODoH routes exclusively with [dnscrypt-proxy_config_generator](https://github.com/possiblynaught/dnscrypt-proxy_config_generator) submodule
7. Makes a backup of /etc/resolv.conf -> /etc/resolv.conf.old and updates the file with the new *listen_addresses*
8. Copy extracted dnscrypt binary/config to dir specified by variable: *INSTALL_DIRECTORY*, defaults to */etc/dnscrypt-proxy/*
9. Install, enable, and start the dnscrypt-proxy service
10. Prompt user if they want to test DNS servers with the [minimal_dnsleaktest](https://github.com/possiblynaught/minimal_dnsleaktest) submodule.

## INSTALL

To install and configure dnscrypt-proxy 2, clone this repository, initialize the submodules, and trigger the install script:

```bash
git clone https://github.com/possiblynaught/install_anonymous_dnscrypt-proxy.git
cd install_anonymous_dnscrypt-proxy/
git submodule init
git submodule update
./install_dnscrypt.sh
```

## TODO

- [x] Add minisign submodule
- [x] Add DNS tester to end of script
- [x] Add instructions
- [x] Create better install locations/perms
