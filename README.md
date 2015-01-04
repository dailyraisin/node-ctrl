# Node-Ctrl

Keep a node service running perpetually with the use of a bash loop and pids. 

    node-ctrl.sh /full/path/app.js {port} {start|stop|restart} [--debug]

`--debug` is optional and exports `DEBUG=*` for node debugging.
