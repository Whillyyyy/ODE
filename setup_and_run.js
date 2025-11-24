#!/usr/bin/env node
const { execSync, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const ROOT = process.cwd();
const SCHEMA = path.join(ROOT, 'db', 'schema.sql');

// Read env overrides from process.env or defaults
const DB_HOST = process.env.DB_HOST || '127.0.0.1';
const DB_NAME = process.env.DB_NAME || 'urs_biometric';
const DB_USER = process.env.DB_USER || 'root';
const DB_PASS = process.env.DB_PASS || '';
const ENCRYPTION_KEY = process.env.ENCRYPTION_KEY || '';

function run(cmd) {
  console.log('>', cmd);
  return execSync(cmd, { stdio: 'inherit', shell: true });
}

async function main() {
  console.log('Setup runner starting. Using DB:', DB_USER + '@' + DB_HOST + '/' + DB_NAME);

  // Import DB schema if file exists
  if (fs.existsSync(SCHEMA)) {
    try {
      const importCmd = DB_PASS ?
        `mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < "${SCHEMA}"` :
        `mysql -h ${DB_HOST} -u ${DB_USER} ${DB_NAME} < "${SCHEMA}"`;
      console.log('Importing DB schema (may require mysql client)...');
      run(importCmd);
    } catch (e) {
      console.error('DB import failed (continuing). Ensure schema is imported manually if needed.');
    }
  } else {
    console.warn('Schema file not found at', SCHEMA);
  }

  // Prepare environment object for child processes (DB and encryption)
  const env = Object.assign({}, process.env, {
    DB_HOST, DB_NAME, DB_USER, DB_PASS,
    ENCRYPTION_KEY
  });

  // Run non-interactive PHP scripts to create admin and seed data
  try {
    console.log('Creating admin user (non-interactive).');
    // default admin credentials (change after first run)
    run(`php "${path.join('api','scripts','create_admin_cli.php')}" --username=admin --password=admin123 --name="Administrator"`);
  } catch (e) {
    console.error('Create admin script failed (it may already exist).');
  }

  try {
    console.log('Seeding sample data.');
    run(`php "${path.join('api','scripts','seed_sample_cli.php')}"`);
  } catch (e) {
    console.error('Seeding failed (continuing).');
  }

  // Start PHP server and admin app; run them as child processes and inherit stdio
  console.log('Starting PHP dev server...');
  const phpProc = spawn('php', ['-S', 'localhost:8000', '-t', 'api'], { env, cwd: ROOT, stdio: 'inherit' });

  // Wait a moment then start admin app
  setTimeout(() => {
    console.log('Starting admin app (dotnet run)...');
    const dotnetProc = spawn('dotnet', ['run', '--project', path.join('admin','URS.Admin.csproj')], { env, cwd: ROOT, stdio: 'inherit' });

    dotnetProc.on('exit', (code) => {
      console.log('Admin app exited with code', code);
      try { phpProc.kill(); } catch(e){}
      process.exit(code);
    });
  }, 1500);

  // When the main process receives SIGINT, forward it
  process.on('SIGINT', () => {
    console.log('Received SIGINT, shutting down child processes...');
    try { phpProc.kill(); } catch (e) {}
    process.exit(0);
  });
}

main();
