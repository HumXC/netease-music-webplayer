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

使用 Nix 直接运行本地 checkout：

```sh
nix run .#
```

使用 Nix 构建：

```sh
nix build .#
```

## 在 NixOS / Flake 中使用

本项目提供 `packages` 和 `overlays.default`。

### 作为 flake package 使用

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    netease-music-webplayer.url = "github:HumXC/netease-webplayer";
  };

  outputs = { nixpkgs, netease-music-webplayer, ... }:
    let
      system = "x86_64-linux";
    in {
      nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ({ ... }: {
            environment.systemPackages = [
              netease-music-webplayer.packages.${system}.default
            ];
          })
        ];
      };
    };
}
```

### 作为 overlay 使用

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    netease-music-webplayer.url = "github:HumXC/netease-webplayer";
  };

  outputs = { nixpkgs, netease-music-webplayer, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.overlays = [
            netease-music-webplayer.overlays.default
          ];

          environment.systemPackages = [
            pkgs.netease-music-webplayer
          ];
        })
      ];
    };
  };
}
```

## Cachix 二进制缓存

项目提供 Cachix 缓存，可避免在本地完整编译 WebKitGTK 等依赖。

缓存配置已经写在本项目的 `flake.nix` 的 `nixConfig` 中。首次运行时，Nix 可能会询问是否信任该 flake 提供的额外 substituter 和 public key，确认后即可使用缓存。

直接运行远程 flake：

```sh
nix run github:HumXC/netease-webplayer
```

构建本地 checkout：

```sh
nix build .#
```

如果你的 Nix 配置禁止接受 flake 的 `nixConfig`，也可以用 Cachix CLI 手动启用：

```sh
cachix use netease-music-webplayer
```

## 非 Nix 环境构建

需要 Zig **0.16.0**。

还需要安装 GTK / WebKitGTK / GStreamer 相关开发包和工具：

- `zig` 0.16.0
- C 编译器，例如 `gcc` 或 `clang`
- `pkg-config`
- `python3`（构建脚本会临时 patch 第三方 Zig 依赖）
- GTK4 开发库
- WebKitGTK 6.0 开发库
- JavaScriptCoreGTK 6.0 开发库（通常随 WebKitGTK 6.0 提供）
- GLib / GObject / GIO 开发库
- libsoup 3 开发库
- glib-networking（运行时 TLS 支持）
- GStreamer 1.0 及常用插件：
  - gstreamer
  - gst-plugins-base
  - gst-plugins-good
  - gst-plugins-ugly
  - gst-libav

Debian / Ubuntu 系发行版包名可能类似：

```sh
sudo apt install \
  zig pkg-config python3 gcc \
  libgtk-4-dev libwebkitgtk-6.0-dev \
  libglib2.0-dev libsoup-3.0-dev \
  glib-networking \
  gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-ugly \
  gstreamer1.0-libav
```

不同发行版包名可能不同；关键是 `pkg-config` 能找到 `gtk4`、`webkitgtk-6.0`、`javascriptcoregtk-6.0` 等依赖。

构建：

```sh
zig build
./zig-out/bin/netease-music-webplayer
```

也可以进入 Nix 开发环境后用 Zig 构建：

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
