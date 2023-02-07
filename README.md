# dnscrypt-proxy config generator

Script to install dnscrypt-proxy2 on linux x86/64 targets, uses randomized Anonymous DNS and Oblivious DNS over HTTPS config by default.

## INFO

This script will:
1. Check for Linux x86_64 target
2. Check for existing dnscrypt-proxy v1
3. Check for existing dnscrypt-proxy v2
4. Download dnscrypt-proxy2 tarball
5. Build + install (statically linked) minisign if not installed and verify tarball with minisig. Skip this step by uncommenting ***SKIP_VERIFY=1***
6. Generate the dnscrypt-proxy.toml config with Anonymous DNS + ODoH routes exclusively with [dnscrypt-proxy_config_generator](https://github.com/possiblynaught/dnscrypt-proxy_config_generator) submodule
7. Makes a backup of /etc/resolv.conf -> /etc/resolv.conf.old and updates the file with the new *listen_addresses*
8. Copy extracted dnscrypt binary/config to dir specified by variable: *INSTALL_LOCATION*, defaults to *$HOME/Documents/dnscrypt-proxy/*
9. Installs and starts the dnscrypt-proxy service
10. Tests DNS servers with [minimal_dnsleaktest](https://github.com/possiblynaught/minimal_dnsleaktest) submodule. Skip this step by uncommenting ***SKIP_DNSLEAKTEST=1***

## INSTALL

To install and configure dnscrypt-proxy2, clone this repository, initialize the submodules, and trigger the install script:

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
- [ ] Create better install locations/perms
