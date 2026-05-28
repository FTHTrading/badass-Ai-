module.exports = {
  apps: [{
    name: 'troptions-os',
    script: 'node_modules/tsx/dist/cli.mjs',
    args: 'server/index.ts',
    cwd: 'C:/Users/Kevan/troptions-os/apps/nano-bana-3d',
    interpreter: 'node',
    env: { NODE_ENV: 'development', PORT: '5000' },
    autorestart: true,
    max_restarts: 10,
    restart_delay: 2000,
    watch: false,
    out_file: 'C:/Users/Kevan/.pm2/logs/troptions-os-out.log',
    error_file: 'C:/Users/Kevan/.pm2/logs/troptions-os-error.log'
  }]
}
