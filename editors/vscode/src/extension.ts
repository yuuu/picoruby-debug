import * as vscode from 'vscode';
import { PicoRubyDebugAdapter } from './debugAdapter';

class PicoRubyDebugAdapterDescriptorFactory implements vscode.DebugAdapterDescriptorFactory {
  createDebugAdapterDescriptor(
    session: vscode.DebugSession
  ): vscode.ProviderResult<vscode.DebugAdapterDescriptor> {
    const config = session.configuration;
    if (typeof config.port !== 'number') {
      void vscode.window.showErrorMessage('PicoRuby: launch.json is missing "port" (see Debugger.listen_dap on the device).');
      return undefined;
    }
    const host = typeof config.host === 'string' ? config.host : 'localhost';
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? '.';
    const localRoot = typeof config.localRoot === 'string' ? config.localRoot : workspaceFolder;

    return new vscode.DebugAdapterInlineImplementation(
      new PicoRubyDebugAdapter(host, config.port, localRoot)
    );
  }
}

export function activate(context: vscode.ExtensionContext): void {
  context.subscriptions.push(
    vscode.debug.registerDebugAdapterDescriptorFactory('picoruby', new PicoRubyDebugAdapterDescriptorFactory())
  );
}

export function deactivate(): void {
  // Nothing to clean up: each PicoRubyDebugAdapter owns and closes its own
  // socket in dispose(), which VS Code calls when its debug session ends.
}
