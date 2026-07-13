# PicoRuby Debug (VS Code)

Attaches VS Code's debugger UI to picoruby-debug's DAP server
(`Debugger.listen_dap`) running on a device (e.g. an ESP32 over WiFi). See the
main [README](../../README.md)'s "DAP support" section for how to start the
server on the device side.

## Usage

1. On the device, run a script that calls `Debugger.listen_dap(port)` before
   its first `binding.debugger` (see `Debugger.listen_dap` in
   `mrblib/debugger.rb`). Note the device's IP address and the port.
2. In VS Code, open the folder containing the same `.rb` source file(s) that
   are running on the device.
3. Add a launch configuration (Run and Debug > "create a launch.json file" >
   "PicoRuby (DAP over WiFi)"), or add this to `.vscode/launch.json`:

   ```json
   {
     "type": "picoruby",
     "request": "attach",
     "name": "Attach to PicoRuby (WiFi DAP)",
     "host": "192.168.1.42",
     "port": 4711,
     "localRoot": "${workspaceFolder}"
   }
   ```

4. Set breakpoints in the editor gutter, then start the "Attach to PicoRuby"
   configuration.

`localRoot` should point at the local directory holding the same source
files the device is running; breakpoints and stack frames are matched by
filename only (not full path), since the device only knows its own on-disk
paths, which don't correspond to paths on your machine.

## Limitations

- `attach` only -- the device is always already running and stopped at a
  `binding.debugger` call by the time you connect; there is no `launch`
  (spawn a process) request.
- One client at a time, matching the device's own one-shot handshake model:
  each `binding.debugger` call accepts exactly one DAP client connection.
