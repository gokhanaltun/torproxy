# torproxy
A Bash script to redirect all outgoing internet traffic through the Tor network on Linux-based systems. It automates configuring Tor, DNS, and iptables rules to ensure your traffic stays anonymous.

## Prerequisites
- The script **must** be run with root privileges (use `sudo`).
- Required packages: `curl`, `iptables`, `netcat (nc)`, and `tor`.
- Make sure Tor is installed and manageable via `systemctl` (system service).

## Usage

Make the script executable:
```bash
sudo chmod +x torproxy.sh
```

Then run it with root privileges:
```bash
sudo ./torproxy.sh
```


### Interactive Commands:
- **s**: Start the Tor proxy.
- **x**: Stop the Tor proxy.
- **c**: Switch Tor identity (request a new IP).
- **i**: Show current public IP address.
- **q**: Quit the script and stop Tor.


## Important Notes:

- This script uses the `debian-tor` user, which is the default for Debian-based systems.
- On non-Debian systems (e.g., Arch, Fedora), you may need to:
  - Create a similar user manually, or
  - Modify the script to use `root` or an appropriate Tor user.
