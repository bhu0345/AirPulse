# Phase 0 — M5 Pro SMC 探针结果

**机型:** Mac17,9（MacBook Pro, Apple M5 Pro）  
**系统:** macOS 26.5.1  
**时间:** 2026-07-31  
**工具:** `airpulse-cli probe`

## 只读结果（已验证）

```
model: Mac17,9
modeKeyFormat: F%dmd
ftstAvailable: false
fanCount: 2
fan[0] actual=0 target=0 min=2317 max=7826 mode=0
fan[1] actual=0 target=0 min=2317 max=7826 mode=0
temp CPU (Tp0O): ~53.7°C
temp GPU (Tg0U): ~47.1°C
temp 电池 (TB1T): ~31.7°C
```

### 解读

| 项 | 结论 |
|----|------|
| 风扇数量 | 双风扇，适合默认联动 |
| 模式 key | `F%dmd`（小写 m），与公开 M5 研究一致 |
| Ftst | **不存在**；应走 direct `mode=1` 写入，无需 Ftst 解锁循环 |
| 冷机 RPM=0 | 正常：系统在低温时可停转；min 报告约 2317 作为建议下限 |
| 温度 key | `Tp0O` / `Tg0U` / `TB1T` 可读，足够做主界面三温 |

## 写入结果

- **无 root：** `airpulse-cli linked` / `preset` 会拒绝（CLI 主动要求 sudo），符合预期。
- **有 root 的 `probe --write`：** 需在本机手动执行（会短暂改转速并恢复 Auto）：

```bash
sudo ./Products/AirPulse.app/Contents/MacOS/airpulse-cli probe --write
```

预期：`strategy=direct`，短暂看到 actual RPM 上升，随后 `restored=auto`。

## 产品含义

本机 **支持继续做完整控风扇产品**（direct 路径）。Helper / sudo CLI 只负责提权写 SMC；UI 与联动逻辑不依赖 Ftst。
