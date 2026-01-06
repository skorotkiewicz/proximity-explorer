# Example service file

```sh
[Unit]
Description=proximity_game
After=network.target

[Service]
ExecStart=/usr/local/bin/cleoselene /home/cleoselene/proximity-explorer/proximity_game.lua
WorkingDirectory=/home/cleoselene/proximity-explorer
Restart=always

[Install]
WantedBy=default.target
```

# Run on user
```sh
$ nano ~/.config/systemd/user/proximity_game.service
$ systemctl --user enable proximity_game.service
$ systemctl --user start proximity_game.service
```

# Run on system
```sh
$ sudo nano /etc/systemd/system/proximity_game.service
$ sudo systemctl enable proximity_game.service
$ sudo systemctl start proximity_game.service
```