# Chalice, a Gemini server
Made from Crystal, by ieve in Winter of 2025
![A crystal chalice](logo.png)


# Requirements
* Crystal lang
* OpenSSL

# Development target
Developed / tested on:
Crystal 1.15.1 (2025-02-08) / LLVM: 19.1.7 / x86_64-pc-linux-gnu

# Development usage
* Generate key and cert
```
openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -subj "/CN={hostname}
```
* Compile and run with debugger enabled
```
crystal i chalice.cr
```

# Production installation / usage
**Clone, alter settings and build**
0. Clone repository
```
git clone git@github.com:CameronCarroll/chalice.git
```

1. Update settings inside the source file prior to compiling, at a minimum set hostname
```
# === User Configuration Stuff: ===
HOSTNAME = "localhost"          # "example.com" or "localhost"
PORT = 1965                     # int32, not a string please
SERVE_DIRECTORY = "/srv/gemini" # /srv/{protocol} is canon I think?
DEFAULT_FILE = "index.gmi"      # filename to be served at domain root
MAX_CONNECTIONS = 50
LOG_LOCATION = "/var/log/gemini"
```
Notes:
(1) Server will reject requests that don't match hostname.
(2) Port 1965 is the default Gemini port because that's when Gemini flew?... wait, this isn't as clear cut as I thought. Ten crews flew Gemini missions through 1965 and 1966. I didn't realize "gemini" referred to an entire series of space missions. SO I guess it's "1965" because that's when the first one went.

2. Compile
After cloning repo, run "shards build" to compile the chalice binary into ./bin

**Install binary, set up user and folder permissions, set up keys**
0. Copy the binary you just built into /usr/local/bin
```
sudo cp ./bin/chalice /usr/local/bin/chalice
```

1. Create service user
```
sudo useradd --system --no-create-home --shell /usr/sbin/nologin chalice
```
Note - You are making this guy homeless. js

2. Set up serve directory
```
sudo mkdir -p /srv/gemini
sudo chown chalice:chalice /srv/gemini
sudo chmod 750 /srv/gemini
```
(Chalice user can do everything, chalice group can read, everybody else is NOT allowed.)

3. Set up log folder
```
sudo mkdir -p /var/log/chalice
sudo chown chalice:chalice /var/log/chalice
sudo chmod 750 /var/log/chalice
```
(Chalice user can do everything, chalice group can read, everybody else can heck off)

4. Create TLS key and cert
```
sudo mkdir /etc/chalice
cd /etc/chalice
openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -subj "/CN={hostname}
```
(Replace hostname in the above command with eg "example.com" or "localhost")

5. Set permissions on key/cert
```
sudo chmod 400 /etc/chalice/server.key
sudo chmod 444 /etc/chalice/server.crt
```
(Only server user can read key. Everybody can read the cert.)

6. Set up logrotate
Create */etc/logrotate.d/chalice*
```
compress

/var/log/gemini/*.log {
  rotate 5
  mail {your esnail address here}
  size 100k
  sharedscripts
  postrotate
    systemctl restart chalice.service
  endscript
}
```
See https://linux.die.net/man/8/logrotate / 'man logrotate' for config details. This default will keep 5 rotations on disk before removing, and will email old ones to the esnail address listed. Logs roll over at 100k file size and are compressed for storage. Server is restarted because its log file descriptor has gone stale.

7. Set up systemd service entry
Create */etc/systemd/system/chalice.service*
```
[Unit]
Description=Chalice server for Gemini protocol
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/chalice
Restart=on-failure
User=chalice
Group=chalice

[Install]
WantedBy=multi-user.target
```

8. Enable and start service
```
sudo systemctl daemon-reload
sudo systemctl enable chalice.service
sudo systemctl start chalice.service
```

# Gemini reference info
https://geminiprotocol.net/docs/protocol-specification.gmi
