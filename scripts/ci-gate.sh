#!/usr/bin/env bash
# 单一门禁脚本：CI workflow 与上游同步 workflow 共用同一套检查，避免两处漂移。
# 任何一步失败即整条链路失败（set -e），不允许"假绿"。
set -euo pipefail

echo "node: $(node --version)  npm: $(npm --version)"

# 锁文件完整性：npm ci 会在 lock 与 package.json 不一致时直接失败，这是我们要的
npm ci --no-audit --no-fund

npm run build
npm run i18n:validate

npm run test:config-compatibility
npm run test:vault-compatibility
npm run test:web-crypto
npm run test:notifications-security
npm run test:webauthn-connectors

echo "gate: all checks passed"
