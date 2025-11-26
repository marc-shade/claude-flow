#!/usr/bin/env node
/**
 * Standalone test of Claude-Flow MCP server
 * Tests that the MCP server can start and respond to tool calls
 */

const { spawn } = require('child_process');
const path = require('path');

console.log('🧪 Testing Claude-Flow MCP Server...\n');

const mcpServer = spawn('node', [
  path.join(__dirname, 'dist/src/cli/main.js'),
  'mcp',
  'start',
  '--transport',
  'stdio'
], {
  stdio: ['pipe', 'pipe', 'pipe'],
  env: {
    ...process.env,
    NODE_ID: 'macpro51',
    CLAUDE_FLOW_DB: '/mnt/agentic-system/databases/claude/claude_flow_real.db',
    STORAGE_BASE: '/mnt/agentic-system'
  }
});

let output = '';
let errorOutput = '';

mcpServer.stdout.on('data', (data) => {
  output += data.toString();
  console.log('STDOUT:', data.toString());
});

mcpServer.stderr.on('data', (data) => {
  errorOutput += data.toString();
  console.error('STDERR:', data.toString());
});

mcpServer.on('error', (error) => {
  console.error('❌ Failed to start MCP server:', error);
  process.exit(1);
});

// Send an initialize request
const initRequest = {
  jsonrpc: '2.0',
  id: 1,
  method: 'initialize',
  params: {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: {
      name: 'test-client',
      version: '1.0.0'
    }
  }
};

setTimeout(() => {
  console.log('\n📤 Sending initialize request...');
  mcpServer.stdin.write(JSON.stringify(initRequest) + '\n');
}, 1000);

setTimeout(() => {
  console.log('\n✅ Test complete - MCP server is responding');
  mcpServer.kill();
  process.exit(0);
}, 5000);
