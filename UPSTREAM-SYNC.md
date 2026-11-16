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
5. 合并成功 → 未配置 `SYNC_PAT` 时把 `.github/workflows/` 还原为 fork 版本（内置 token 无权改工作流）；配置后跳过此步，工作流随上游一起同步
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

## 4. 工作流同步：双模式，`SYNC_PAT` 是可选项

内置 `GITHUB_TOKEN` **永远**拿不到 `workflows` 权限（GitHub 不允许给 App token 这个 scope，改仓库设置也没用），所以推送含 `.github/workflows/` 改动的提交会被拒。workflow 因此内置两种模式，自动探测：

| 模式 | 触发条件 | 工作流改动 | bot PR 的 CI |
|---|---|---|---|
| `github-token` | 未配置 `SYNC_PAT` | 还原为 fork 版本，改动写进 PR 正文；若上游只改工作流则开 issue 提醒（按标题去重） | **不触发**（GitHub 防递归），结果只看 job 日志 |
| `pat` | 已配置 `SYNC_PAT` | 随上游一起同步 | 自动触发 |

升级到 `pat` 模式（一次性，**不需要改任何代码**）：

1. 建 fine-grained PAT：`Contents` RW + `Workflows` RW + `Pull requests` RW + `Issues` RW，**仅限 `EndDream/nodewarden`**
2. Settings → Secrets and variables → Actions → New repository secret，名称 `SYNC_PAT`
3. Actions → Sync Upstream → Run workflow，验证日志里出现「使用 SYNC_PAT」

当前状态（2026-11-16）：已配置 `SYNC_PAT`，`main` 的必需检查是 `Build & Test`（`strict=false`，管理员可绕过）。

**反向操作顺序**：如果 secret 被删除或 PAT 过期，工作流会自动退回 `github-token` 模式，bot PR 将不再触发 CI。此时**先移除必需检查**，否则 bot PR 会永远等一个不会来的检查。`github-token` 模式下不要设必需检查。

（不建 PAT 也能长期跑，代价是上游对工作流的安全改进要人工搬运，每次同步会在 PR/issue 里列清单。）


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
