# Node.js Web Server — Port 8050

Serves `p1.txt`, `p2.txt`, … `pn.txt` from `webserver/programs/` at endpoints `/p1`, `/p2`, … `/pn`.

## Files

```
webserver/
├── server.js           # Node.js server (port 8050)
├── programs/
│   ├── p1.txt
│   ├── p2.txt
│   └── ...
└── README.md
```

Add more programs by creating `programs/p4.txt`, `programs/p5.txt`, etc. They're served at `/p4`, `/p5` automatically.

## Run on your phone (Termux)

```bash
pkg install nodejs
cd ~/webserver
node server.js
```

It prints your phone's router IP, e.g. `http://192.168.1.5:8050`.

## Use from your laptop (same Wi-Fi)

```bash
curl -s http://<PHONE_IP>:8050/p1 | xclip -selection clipboard
```

Then paste with middle-click or `Ctrl+Shift+V`.

## Ubuntu clipboard

- X11 (default): `xclip -selection clipboard`
- Wayland: `wl-copy`
