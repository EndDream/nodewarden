# DELTA — 自有改动台账

本文件记录 fork 相对上游（`shuaiplus/nodewarden`）的每一处主动偏离，避免"改了但没人记得为什么"。
新增偏离必须登记；上游已吸收的改为 `upstreamed`，不再维护的改为 `drop`。

状态含义：

- `keep` — 上游不会接受，长期保留
- `propose` — 准备回推上游，分支用 `fix/*`
- `upstreamed` — 上游已合入，检查是否可从 fork 删除
- `drop` — 已放弃，等下一次同步覆盖或手动删除

| 改动 | 文件 | 与上游的分歧 | 状态 | 锚点 / 备注 |
|---|---|---|---|---|
| CI 门禁 | `scripts/ci-gate.sh`、`.github/workflows/ci.yml` | 上游无 CI 执行 | `propose` | 上游 9 个 test 脚本此前零执行 |
| 同步链路 | `.github/workflows/sync-upstream.yml` | 上游无此需求 | `keep` | PR 化 + 门禁前置 + 冲突留证 |
| undici override | `package.json`、`package-lock.json` | 上游 8.12.2，本 fork 8.12.3 | `keep` | 上游 `36ffe0a`；同批 GHSA 修复，取最新补丁 |
| 安全扫描修正 | `.github/workflows/security-extra.yml` | `pnpm audit` 假绿 | `propose` | 无 `pnpm-lock.yaml`，改 `npm audit` |
| CodeQL 触发面 | `.github/workflows/codeql.yml` | 缺 PR 与定时扫描 | `propose` | 上游若接受则转 `upstreamed` |
| Dependabot 限额 | `.github/dependabot.yml` | `open-pull-requests-limit: 0` 等于冻结 | `propose` | 改 5 |

## 维护规则

1. 每个 `ds/*`、`fix/*` PR 合并前，在本表加一行，写明文件、分歧点、状态。
2. 每次同步后检查 `upstreamed` 条目：能删的删，减少长期分叉面。
3. 回推上游时把 `propose` 改为 PR 链接；合并后改 `upstreamed` 并注明上游版本。
4. 表里出现 3 条以上 `keep` 且集中在同一目录，就该考虑目录隔离（把自有逻辑挪到独立模块，不再改上游文件）。
