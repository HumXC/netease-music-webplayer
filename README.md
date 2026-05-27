# netease-music-webplayer

网易云音乐 Web 播放器的非官方 WebKitGTK 桌面封装，提供托盘菜单、播放控制、喜欢状态和播放模式切换等功能。

默认打开：<https://music.163.com/st/webplayer>

## 免责声明

本项目是社区/个人维护的非官方项目，与网易、网易云音乐没有任何隶属、授权、赞助或背书关系。

项目中包含的网易云音乐图标/商标素材仅用于标识目标服务及桌面集成用途，其商标、Logo、品牌名称及相关权益归网易或其相应权利人所有。本项目代码本身不授予你对这些商标素材的任何权利；分发或使用时请自行遵守相关商标和版权要求。

## 功能

- WebKitGTK 桌面窗口
- 系统托盘图标
- 托盘菜单显示当前歌曲
- 播放/暂停、上一曲、下一曲
- 添加/取消喜欢
- 播放模式切换：随机播放、顺序播放、心动模式、列表循环、单曲循环
- 登录态、缓存和 Cookie 持久化

## 运行

使用 Nix：

```sh
nix run .#
```

构建：

```sh
nix build .#
```

## Cachix 二进制缓存

项目提供 Cachix 缓存，可避免在本地完整编译 WebKitGTK 等依赖。

一次性使用：

```sh
nix run \
  --extra-substituters https://netease-music-webplayer.cachix.org \
  --extra-trusted-public-keys netease-music-webplayer.cachix.org-1:PKEilRsFVSr1IXF0oFIoGTbJ3Lih7PYH5RII7w0ntzo= \
  .#
```

构建时使用：

```sh
nix build \
  --extra-substituters https://netease-music-webplayer.cachix.org \
  --extra-trusted-public-keys netease-music-webplayer.cachix.org-1:PKEilRsFVSr1IXF0oFIoGTbJ3Lih7PYH5RII7w0ntzo= \
  .#
```

也可以用 Cachix CLI 持久启用：

```sh
cachix use netease-music-webplayer
```

或手动加入 Nix 配置：

```conf
substituters = https://cache.nixos.org https://netease-music-webplayer.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWmJwzgbUyFE4guS7euj6Ct4VbF1E= netease-music-webplayer.cachix.org-1:PKEilRsFVSr1IXF0oFIoGTbJ3Lih7PYH5RII7w0ntzo=
```

或进入开发环境后用 Zig 构建：

```sh
nix develop
zig build
./zig-out/bin/netease-music-webplayer
```

## 命令行参数

```sh
netease-music-webplayer --silent
netease-music-webplayer --auto-play
netease-music-webplayer --silent --auto-play
```

- `--silent` / `-s`：启动后不显示窗口，仅在后台加载并显示托盘图标。
- `--auto-play` / `-a`：启动后尝试自动开始播放。

## 数据目录

运行数据保存在：

```txt
~/.config/netease-music-webplayer/
```

包括 WebKit 数据、缓存和 Cookie。