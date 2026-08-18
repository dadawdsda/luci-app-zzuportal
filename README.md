# luci-app-zzuportal

用于郑州大学 Portal 网络的 OpenWrt LuCI 自动认证插件。插件由 procd 托管，使用
OpenWrt 原生 `logd` 记录运行状态。

接口默认适配主校区松园二期。其他宿舍园或校区的认证接口返回信息可能不同，仅修改页面
中的请求地址仍可能无法使用，此时需要修改源代码进行适配。本项目适用于
OpenWrt/ImmortalWrt 23.05 及以上版本（JavaScript 版 LuCI）。

本项目采用 [MIT License](LICENSE) 开源许可证。


## 自动检测流程

启用后，守护进程按照配置的检测间隔执行以下流程：

1. 确认配置设备存在，并且该设备承载 IPv4 默认路由。否则保持空闲。
2. 按配置顺序使用 ICMP 或 curl 探测 `check_address` 列表；任一地址成功即结束本轮，后续地址不再请求。
3. 每连续失败达到 `failure_threshold` 后，才通过 `info_url` 查询一次 Portal 登录状态；未达到阈值时不请求该接口，任一轮探测成功都会清零计数。
4. `result=1`：Portal 仍显示已登录，将故障视为上游网络问题，不执行恢复。
5. `result=0`：未登录，使用 UCI 中的账号、密码、终端类型和 ISP 发起登录。
6. 登录返回 `ldap auth error` 或“账号不存在”时暂停监控；用户修正账号、密码或 ISP 配置并保存应用后，服务自动恢复。
7. 第三方 ISP 返回 `Rad:`、PPPOE 或代拨认证超时特征时，临时使用 `ZZUWLAN` 再尝试一次。
8. 命中 Portal 强制接管特征：在 UCI 中递增设备 MAC 的最后两个字节，重载网络配置，等待链路稳定后重新登录。
9. 状态接口超时或响应无法识别时，通过 `http://172.16.2.9/` 再执行一次纯 HTTP
   接管探测；明确命中接管特征才修改 MAC，否则记录错误并等待下一轮。

curl 检测地址未填写协议时自动使用 HTTPS，以避免普通 HTTP 请求被 Portal 重定向后误判为互联网可用。

强制接管状态使用以下响应特征识别：

- HTTP 响应头包含 `Server: MAGI`；或
- HTML 同时包含 `location.replace(` 和 `/portal.do?wlanuserip=`。

这些特征来自异常状态下对任意 HTTP 请求返回的强制重定向页面。异常时 801 端口可能
直接超时，因此状态接口失败后还会探测 80 端口。只有明确命中特征时才执行改 MAC，
避免把普通断网误判为 Portal 状态混乱。

## 登录参数

登录请求通过 `curl --data-urlencode` 添加参数，因此账号、Base64 文本以及 URL 中的
特殊字符都会正确转义。

- 校园网：`user_account=,{type},{username}`
- 运营商：`user_account=,{type},{username}@{isp}`
- 密码：明文密码执行标准 Base64 后作为 `user_password`

终端类型为 `0`（PC）或 `1`（移动设备）。ISP 支持 `cmcc`、`unicom`、`telecom`、
`zzuplan`；配置值 `zzuwlan` 代表不添加 ISP 和 `@`。

## 运维

LuCI 页面位于“服务 -> ZZU Portal Tool”，包括状态、设置和日志三个页面。状态页提供
刷新、登录、登出、改 MAC 并重新登录四个动作。日志页显示最近 300 条带有
`zzuportal` 标签的系统日志。

命令行检查：

```sh
/usr/bin/zzuportal --once
logread -e zzuportal
/etc/init.d/zzuportal restart
```

首次安装默认不启用自动认证。填写账号和密码、选择设备并启用后，LuCI 保存应用会通过
procd 配置触发器重新加载服务。

## 脚本接口

内部动作脚本统一位于 `/etc/zzuportal/`，主入口为 `status.sh`、`login.sh`、
`logout.sh`、`change-mac.sh` 和 `relogin.sh`，共享函数位于 `common.sh`。

LuCI 发起“更改 MAC 并重新登录”时使用后台任务执行。页面仅轮询路由器本地任务状态，
不会在链路等待期间占用 rpcd，也不会在任务完成前请求 Portal 状态接口。
