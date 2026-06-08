# 素材署名 (CREDITS)

## 进度条材质（`media/textures/preset_bar_*.tga`）

源自社区开源 LibSharedMedia 生态中标注为"自由分发"的常用 statusbar 纹理，
按其上游 `SharedMediaAttributions` 中的条款使用，重命名后纳入本插件随包发布：

| 本插件文件 | 上游素材 | 备注 |
| --- | --- | --- |
| `preset_bar_smooth.tga`  | `Smooth.tga`  | LSM 经典系列 |
| `preset_bar_glaze.tga`   | `Glaze.tga`   | LSM 经典系列 |
| `preset_bar_glamour.tga` | `Glamour.tga` | LSM 经典系列 |
| `preset_bar_frost.tga`   | `Frost.tga`   | LSM 经典系列 |

原始素材列表见：<https://www.curseforge.com/wow/addons/shared-media-lib>

## 圆环材质（`media/textures/preset_circle_*.tga`）

由本仓库 `Tools/build_circle_presets.py` 脚本程序化生成：取对应 statusbar 纹理
的中央列像素作为径向渐变源（圆心 = statusbar 中线，外缘 = statusbar 底部），
映射到 256×256 圆形 + 4px 抗锯齿边缘 alpha。视觉上与同名 statusbar 保持一致
（玻璃管剖面 → 球面光感）。

| 本插件文件 | 派生自 |
| --- | --- |
| `preset_circle_smooth.tga`  | `preset_bar_smooth.tga`  径向采样 |
| `preset_circle_glaze.tga`   | `preset_bar_glaze.tga`   径向采样 |
| `preset_circle_glamour.tga` | `preset_bar_glamour.tga` 径向采样 |
| `preset_circle_frost.tga`   | `preset_bar_frost.tga`   径向采样 |

派生作品延用上游 statusbar 素材的许可条款。

## 反馈

如果原作者认为某张素材的署名/许可需要调整，请提 issue，我会立即处理。
