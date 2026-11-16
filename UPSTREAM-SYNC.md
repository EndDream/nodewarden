# 上游同步手册

上游：[shuaiplus/nodewarden](https://github.com/shuaiplus/nodewarden)（Bitwarden 兼容服务端，Cloudflare Workers）
本仓库：EndDream/nodewarden（fork，LGPL-3.0）

> `docs/` 在上游的 `.gitignore` 里，所以本文件放在仓库根目录，避免被忽略。

## 1. 分支模型（A 方案）

| 分支 | 角色 | 谁能写 | 规则 |
|---|---|---|---|
| `main` | 发布分支，部署与 Release 都从这里出 | 仅 PR | 受保护：必须 PR、禁止强推、禁止删除 |
| `mirror/upstream` | 上游 `main` 的只读镜像，用于对比与回溯 | 仅同步 job 自动刷新 | 禁止任何人工提交 |
| `sync/upstream-YYYY-MM-DD` | 每次同步的临时集成分支 | 同步 bot | 门禁通过后开 PR，合并后删除 |
| `ds/*` | 自有功能/方向改动 | 人工 | 从 `main` 拉出，小步提 PR |
| `fix/*` | 上游可接受的通用修复（准备回推） | 人工 | 与自有功能严格分开，便于单独回推 |

铁律：**机器人不直接写 `main`，人不在 `mirror/upstream` 上提交，自有功能不直接改上游核心文件。**

## 2. 每日同步怎么跑

`.github/workflows/sync-upstream.yml`，每天 UTC 03:17 或手动触发：

1. fetch `upstream/main`，无新提交则直接退出
2. 刷新 `mirror/upstream` 为上游 `main` 的精确副本
3. 从 `main` 建 `sync/upstream-<日期>`，`git merge --no-ff upstream/main`
4. 冲突 → `git merge --abort` + 开 issue 留证 + 失败退出，**不自动取舍**
5. 合并成功 → 把 `.github/workflows/` 还原为 fork 版本（`GITHUB_TOKEN` 无权改工作流）
6. 跑 `scripts/ci-gate.sh`（与 CI 同一套检查），失败则不开 PR
7. 推送分支 → 开 PR，正文附上游提交清单与「被覆盖的工作流改动」清单

合并由人工完成：看 PR 正文、看 job 日志里的门禁结果，确认后合并。

## 3. 冲突怎么处理

| 类型 | 判断 | 处理 |
|---|---|---|
| 文本冲突 | `git status` 里的 `UU` | 小步高频同步可把冲突面压到最小；重复冲突的文件开 `git rerere` |
| **语义冲突** | Git 无冲突，但行为变了 | 只能靠门禁：`ci-gate.sh` 全绿 + 人工确认 backup/schema/client 兼容 |
| 依赖与锁文件 | `package.json` overrides、`package-lock.json` | 取**较高补丁版本**，然后 `npm install --package-lock-only` 重生成锁；不要两边各留一份 |
| 数据库 schema | `migrations/`、`storage-schema.ts`、`STORAGE_SCHEMA_VERSION` | 自有迁移用 `9xxx_` 高段号；schema 版本用独立变量；备份白名单显式登记新字段 |
| 工作流 | `.github/workflows/*` | 见第 4 节；涉及权限/触发器的上游改动优先人工搬运 |
| i18n | `webapp/src/lib/i18n/locales/*` | 必须全量同步，`npm run i18n:validate` 把关 |

高风险文件（上游 `CONTRIBUTING.md` 点名）：`src/services/storage-schema.ts`、`migrations/0001_init.sql`、`src/services/storage.ts`、`src/services/backup-archive.ts`、`src/services/backup-import.ts`、`src/handlers/ciphers.ts`、`src/handlers/sync.ts`、`src/services/storage-cipher-repo.ts`。

## 4. 已知限制：工作流不会自动同步

`GITHUB_TOKEN` 无权创建或修改 `.github/workflows/` 下的文件，所以同步时会整体还原为 fork 版本。后果：

- 上游对工作流的安全改进**不会自动到达**
- 每次同步在 PR 正文里列出被覆盖的文件；若上游只改工作流，会单独开 issue 提醒，且不会重复开（按标题去重）

升级路径（需要人工建 PAT，机器做不到）：

1. 建 fine-grained PAT：Contents 读写 + Workflows 读写，仅限本仓库
2. 存为 **environment** secret `SYNC_PAT`（Settings → Environments → `sync-upstream`）
3. job 加 `environment: sync-upstream`，checkout 用 `token: ${{ secrets.SYNC_PAT }}`
4. 删除 `Keep fork workflow files` 一步

升级后 PR 也会自动触发 CI（`GITHUB_TOKEN` 创建的 PR 不会，这是 GitHub 防递归机制），届时应把 `Build & Test` 设为必需检查。

## 5. 双向同步（回推上游）

只回推**无方向分歧**的改动：CI 加固、安全依赖升级、bugfix、i18n、客户端兼容修复。

- 上游接受社区 PR（历史 PR #425、#415、#395 均合并），通道可用
- 从 `main` 拉 `fix/*`，一个 PR 只做一件事，附本地验证命令与结果
- 带产品方向分歧的功能不回推：走 issue/RFC 讨论，或做成独立扩展目录
- 每条自有补丁在 [DELTA.md](DELTA.md) 登记状态：`keep` / `propose` / `upstreamed` / `drop`

## 6. 发布与回滚

- 发布对齐上游 release tag（当前 `v1.8.1`），不追每次 commit
- 每次同步合并前打 tag：`pre-sync-YYYY-MM-DD`，出问题 `git revert -m 1 <merge>` 或用 tag 回滚
- 禁止对 `main` 使用 `--force`；同步分支允许 `--force-with-lease`（bot 专用）
- 许可证：LGPL-3.0。分发派生版本必须同许可证、保留版权声明、提供对应源码
- 已知上游缺陷：`test:folder-tree` 指向不存在的 `scripts/folder-tree.test.ts`，暂未纳入门禁，待上游修复
