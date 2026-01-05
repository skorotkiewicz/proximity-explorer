
[Unit]
Description=cleoselene
After=network.target

[Service]
ExecStart=/home/mod/.cleoselene/bin/cleoselene /home/mod/cleoselene/proximity-explorer/proximity_game.lua
WorkingDirectory=/home/mod/cleoselene/proximity-explorer
Restart=always

[Install]
WantedBy=default.target

# nano ~/.config/systemd/user/cleoselene.service
# systemctl --user enable cleoselene.service
# systemctl --user start cleoselene.service