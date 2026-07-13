import * as net from 'net';
import * as path from 'path';
import * as vscode from 'vscode';

// picoruby-debug's DapSession speaks the DAP wire protocol directly over a
// plain TCP socket (Content-Length-framed JSON, same framing VS Code itself
// uses) -- see dap_session.rb / dap_transport.rb. This class is a thin proxy
// between that socket and VS Code's DebugAdapter interface: it does not
// reimplement DAP semantics (initialize/attach/continue/... are just
// forwarded verbatim), it only fixes up file paths, which need translation
// in both directions -- see the two comments below for why.
export class PicoRubyDebugAdapter implements vscode.DebugAdapter {
  private readonly onDidSendMessageEmitter = new vscode.EventEmitter<vscode.DebugProtocolMessage>();
  readonly onDidSendMessage = this.onDidSendMessageEmitter.event;

  private readonly socket: net.Socket;
  private recvBuffer = Buffer.alloc(0);
  private disposed = false;

  constructor(host: string, port: number, private readonly localRoot: string) {
    this.socket = net.createConnection({ host, port });
    this.socket.on('data', (chunk) => this.onData(chunk));
    this.socket.on('error', (err) => this.onSocketClosed(err.message));
    this.socket.on('close', () => this.onSocketClosed());
  }

  handleMessage(message: DebugProtocol.ProtocolMessage): void {
    if (isRequest(message, 'setBreakpoints')) {
      // The device matches breakpoints by checking whether the *running*
      // file's path ends with the path we send here (debug_file_match in
      // src/mruby/line_breakpoint.c). VS Code always sends a full local
      // absolute path, which is longer than the short path the device
      // reports for itself (e.g. "./dap_debug_sample.rb") -- so a suffix
      // check the other way around never succeeds. Sending just the
      // filename guarantees it's a valid suffix instead.
      const args = (message as any).arguments;
      const sourcePath = args?.source?.path;
      if (typeof sourcePath === 'string') {
        args.source.path = basename(sourcePath);
      }
    }
    this.sendToSocket(message);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.socket.destroy();
  }

  private sendToSocket(message: unknown): void {
    if (this.socket.destroyed) {
      return;
    }
    const body = Buffer.from(JSON.stringify(message), 'utf8');
    const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, 'utf8');
    this.socket.write(Buffer.concat([header, body]));
  }

  private onData(chunk: Buffer): void {
    this.recvBuffer = Buffer.concat([this.recvBuffer, chunk]);
    for (;;) {
      const headerEnd = this.recvBuffer.indexOf('\r\n\r\n');
      if (headerEnd === -1) {
        return;
      }
      const header = this.recvBuffer.subarray(0, headerEnd).toString('utf8');
      const match = /Content-Length:\s*(\d+)/i.exec(header);
      if (!match) {
        // Not a message we understand; drop the buffer rather than spin.
        this.recvBuffer = Buffer.alloc(0);
        return;
      }
      const length = parseInt(match[1], 10);
      const bodyStart = headerEnd + 4;
      const bodyEnd = bodyStart + length;
      if (this.recvBuffer.length < bodyEnd) {
        return; // wait for the rest of the body
      }
      const body = this.recvBuffer.subarray(bodyStart, bodyEnd).toString('utf8');
      this.recvBuffer = this.recvBuffer.subarray(bodyEnd);
      this.handleDeviceMessage(JSON.parse(body));
    }
  }

  private handleDeviceMessage(message: DebugProtocol.ProtocolMessage): void {
    if (isResponse(message, 'stackTrace')) {
      // Mirror image of the setBreakpoints rewrite: the device reports its
      // own short path (e.g. "./dap_debug_sample.rb"), which isn't a real
      // path from VS Code's point of view. Resolve it against localRoot so
      // the editor can open/highlight the right file.
      const frames = (message as any).body?.stackFrames;
      if (Array.isArray(frames)) {
        for (const frame of frames) {
          const sourcePath = frame?.source?.path;
          if (typeof sourcePath === 'string') {
            frame.source.path = path.join(this.localRoot, basename(sourcePath));
          }
        }
      }
    }
    this.onDidSendMessageEmitter.fire(message as vscode.DebugProtocolMessage);
  }

  private onSocketClosed(reason?: string): void {
    if (this.disposed) {
      return;
    }
    if (reason) {
      this.onDidSendMessageEmitter.fire({
        seq: 0,
        type: 'event',
        event: 'output',
        body: { category: 'stderr', output: `picoruby-debug connection closed: ${reason}\n` },
      } as vscode.DebugProtocolMessage);
    }
    this.onDidSendMessageEmitter.fire({ seq: 0, type: 'event', event: 'terminated' } as vscode.DebugProtocolMessage);
  }
}

function basename(p: string): string {
  return p.replace(/\\/g, '/').split('/').pop() ?? p;
}

function isRequest(message: DebugProtocol.ProtocolMessage, command: string): boolean {
  return message.type === 'request' && (message as any).command === command;
}

function isResponse(message: DebugProtocol.ProtocolMessage, command: string): boolean {
  return message.type === 'response' && (message as any).command === command;
}

// Minimal structural typing for the bits of the DAP message shapes this file
// touches -- avoids taking a dependency on @vscode/debugprotocol just for
// types.
namespace DebugProtocol {
  export interface ProtocolMessage {
    seq: number;
    type: string;
  }
}
