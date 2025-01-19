# torproxy
This script automates the management of a Tor proxy service on a Linux-based system. Redirects all network communication to the Tor network.

## Prerequisites:
- The script requires **sudo** (root privileges) to run properly.
- Ensure **curl**, **iptables**, **netcat** and **tor** are installed and properly configured.
- The script assumes that Tor is installed and available as a system service (systemctl).

## Usage:
To make the file executable:  

```bash
chmod +x ./torproxy.sh
``` 

To use the script, run it with root privileges:

```bash
sudo ./torproxy.sh
```


### Interactive Commands:
- **s**: Start the Tor proxy.
- **x**: Stop the Tor proxy.
- **c**: Switch Tor identity (request a new IP).
- **i**: Show current public IP address.
- **q**: Quit the script and stop Tor.


## Important Note:  
The script uses the `debian-tor` user, which is the default user for managing Tor processes on Debian-based systems. However, this user may not be available on all Linux distributions.  

- If you are using Arch or another distribution, you might need to create a similar user or modify the script to work with root (or an existing user).  

**I plan to update the script soon to remove this limitation.**
