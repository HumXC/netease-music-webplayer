# netease-music-webplayer

一个轻量级的 Linux 网易云音乐 Web 播放器启动器与桌面集成工具。

项目不会内嵌 WebKit/WebView，而是启动系统中已有的 **Chromium/CDP 兼容浏览器**，以应用模式打开网易云音乐 Web 播放器，并通过 Chrome DevTools Protocol（CDP）实现播放控制和状态读取。

默认打开：

<https://music.163.com/st/webplayer>

## 特性

* 使用系统已有的 Chromium 系浏览器，无需捆绑浏览器内核
* 以 Chromium `--app` 模式运行网易云音乐 Web 播放器
* 自动寻找可用的 Chromium/CDP 兼容浏览器
* 支持通过命令行指定浏览器
* 独立浏览器 Profile，保留登录状态、Cookie 和站点数据
* 通过 CDP 控制网易云音乐网页
* Linux StatusNotifierItem 系统托盘集成
* D-Bus Menu 托盘菜单
* 显示当前播放歌曲
* 播放 / 暂停
* 上一曲 / 下一曲
* 添加喜欢 / 取消喜欢
* 静音 / 取消静音
* 播放模式切换：

  * 随机播放
  * 顺序播放
  * 心动模式
  * 列表循环
  * 单曲循环
* 从托盘重新显示播放器窗口
* 从托盘退出播放器
* 可选启动后自动播放
* 支持 x86_64 和 aarch64
* Nix 构建使用 musl target，降低对目标发行版 glibc 版本的依赖
* 可生成 DEB、RPM 和 Arch Linux 安装包

## 工作原理

项目本身不负责网页渲染。

大致结构如下：

```text
netease-music-webplayer
        │
        ├── browser.zig
        │     └── 启动 Chromium --app
        │
        ├── cdp.zig
        │     ├── 获取 Chromium DevTools target
        │     └── WebSocket / Chrome DevTools Protocol
        │
        ├── player.zig
        │     └── 通过 CDP 调用网页 JavaScript
        │
        └── tray.zig
              └── Goose / D-Bus
                    ├── StatusNotifierItem
                    └── DBusMenu
```

CDP WebSocket 使用 [`websocket.zig`](https://github.com/karlseguin/websocket.zig)，Linux D-Bus 集成使用 [`Goose`](https://github.com/luxluth/goose)。

项目不再依赖 libcurl、WebKitGTK、GTK 或 GStreamer。

## 浏览器要求

需要安装至少一个 Chromium/CDP 兼容浏览器。

程序可以自动检测常见浏览器，包括：

* Chromium
* Google Chrome
* Brave
* Vivaldi
* Microsoft Edge
* Thorium
* Ungoogled Chromium

也可以使用其他 Chromium 系浏览器，只要它支持 Chrome DevTools Protocol。

### Firefox 不受支持

Firefox 系浏览器没有 Chromium CDP，因此无法用于本项目，包括：

* Firefox
* Zen Browser
* LibreWolf
* Floorp
* Waterfox
* Mullvad Browser
* Tor Browser

## 安装

### GitHub Release

Release 提供以下架构：

```text
x86_64
aarch64
```

以及多种发行格式：

```text
裸 Linux 二进制
.deb
.rpm
.pkg.tar.zst
```

裸二进制可以直接运行：

```sh
chmod +x netease-music-webplayer-linux-x86_64
./netease-music-webplayer-linux-x86_64
```

### Debian / Ubuntu

下载对应的 `.deb` 后：

```sh
sudo apt install ./netease-music-webplayer_*.deb
```

### Fedora / RHEL 系

下载对应的 `.rpm` 后：

```sh
sudo dnf install ./netease-music-webplayer-*.rpm
```

### Arch Linux

下载对应的 `.pkg.tar.zst` 后：

```sh
sudo pacman -U ./netease-music-webplayer-*.pkg.tar.zst
```

## 使用 Nix

直接运行远程 Flake：

```sh
nix run github:HumXC/netease-music-webplayer
```

构建当前平台版本：

```sh
nix build .#
```

运行本地 checkout：

```sh
nix run .#
```

### 指定目标架构

构建 x86_64：

```sh
nix build .#x86_64-linux
```

构建 aarch64：

```sh
nix build .#aarch64-linux
```

由于实际目标由 Zig 负责交叉编译，因此在 x86_64 Linux 主机上也可以构建 aarch64 Linux 二进制。

### 构建发行版安装包

Debian / Ubuntu：

```sh
nix build .#deb-x86_64
nix build .#deb-aarch64
```

RPM：

```sh
nix build .#rpm-x86_64
nix build .#rpm-aarch64
```

Arch Linux：

```sh
nix build .#arch-x86_64
nix build .#arch-aarch64
```

发行版安装包由 Nix 调用 nFPM 构建。

## 在 NixOS Flake 中使用

例如：

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    netease-music-webplayer.url =
      "github:HumXC/netease-music-webplayer";
  };

  outputs = {
    nixpkgs,
    netease-music-webplayer,
    ...
  }: {
    nixosConfigurations.your-host =
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          {
            environment.systemPackages = [
              netease-music-webplayer.packages.x86_64-linux.default
            ];
          }
        ];
      };
  };
}
```

## Cachix

项目配置了 Cachix 二进制缓存：

```text
netease-music-webplayer.cachix.org
```

Flake 中已经包含对应的 substituter 和 public key。

使用远程 Flake 时：

```sh
nix run github:HumXC/netease-music-webplayer
```

Nix 可能会询问是否信任 Flake 提供的额外缓存配置。

也可以手动启用：

```sh
cachix use netease-music-webplayer
```

## 命令行参数

查看帮助：

```sh
netease-music-webplayer --help
```

### 自动选择浏览器

```sh
netease-music-webplayer
```

程序会寻找可用的 Chromium 系浏览器。

### 指定浏览器

```sh
netease-music-webplayer --browser chromium
```

或者：

```sh
netease-music-webplayer -b chromium
```

支持的快捷名称包括：

```text
auto
chromium
chrome
brave
vivaldi
edge
```

也可以直接提供可执行文件：

```sh
netease-music-webplayer \
  --browser /path/to/chromium
```

或者其他 Chromium 系浏览器命令：

```sh
netease-music-webplayer \
  --browser thorium-browser
```

### 自动播放

```sh
netease-music-webplayer --auto-play
```

简写：

```sh
netease-music-webplayer -a
```

也可以组合：

```sh
netease-music-webplayer \
  --browser brave \
  --auto-play
```

## 数据目录

浏览器 Profile 保存在：

```text
~/.config/netease-music-webplayer/browser-profile/
```

其中包含网易云音乐 Web 端的登录状态、Cookie、Local Storage 以及 Chromium 站点数据。

删除这个目录相当于重置播放器的浏览器 Profile：

```sh
rm -rf ~/.config/netease-music-webplayer/browser-profile
```

执行后需要重新登录网易云音乐。

## 从源码构建

需要：

* Zig 0.16.0
* Git
* Chromium/CDP 兼容浏览器

项目的 Zig 依赖包括：

* [Goose](https://github.com/luxluth/goose)
* [websocket.zig](https://github.com/karlseguin/websocket.zig)

进入开发环境：

```sh
nix develop
```

如果 Goose 依赖需要应用项目提供的 Zig 0.16 兼容补丁：

```sh
zig build patch-goose
```

然后构建：

```sh
zig build -Doptimize=ReleaseSmall
```

产物：

```text
zig-out/bin/netease-music-webplayer
```

运行：

```sh
./zig-out/bin/netease-music-webplayer
```

### 使用 musl 构建

x86_64：

```sh
zig build \
  -Dtarget=x86_64-linux-musl \
  -Doptimize=ReleaseSmall
```

aarch64：

```sh
zig build \
  -Dtarget=aarch64-linux-musl \
  -Doptimize=ReleaseSmall
```

Nix 构建默认使用对应架构的 musl target。

## 项目结构

```text
.
├── assets/
├── patches/
├── src/
│   ├── main.zig
│   ├── browser.zig
│   ├── cdp.zig
│   ├── player.zig
│   └── tray.zig
├── build.zig
├── build.zig.zon
├── deps.nix
├── packaging.nix
└── flake.nix
```

主要模块：

* `browser.zig`：浏览器检测、选择和启动
* `cdp.zig`：CDP HTTP / WebSocket 通信
* `player.zig`：网易云音乐播放器状态和控制
* `tray.zig`：StatusNotifierItem 与 DBusMenu
* `deps.nix`：Zig 依赖的 Nix 固定输出
* `packaging.nix`：DEB / RPM / Arch Linux 包构建
* `patches/`：第三方依赖兼容补丁

## 图标来源

项目使用的网易云音乐 SVG 图标来源于 Flathub 的 [`com.netease.CloudMusic`](https://github.com/flathub/com.netease.CloudMusic) 项目：

[`com.netease.CloudMusic.svg`](https://github.com/flathub/com.netease.CloudMusic/blob/master/com.netease.CloudMusic.svg)

该图标仅用于标识网易云音乐服务及桌面集成。

网易云音乐名称、Logo、商标及相关品牌资产的权利归网易或相应权利人所有。

## 免责声明

本项目是社区 / 个人维护的**非官方项目**，与网易、网易云音乐不存在任何隶属、授权、赞助或背书关系。

本项目通过 Chromium DevTools Protocol 和网页 JavaScript 与网易云音乐 Web 播放器进行集成。网易云音乐网页结构或行为发生变化后，部分功能可能失效。

本项目由 AI 驱动开发。代码、构建脚本、文档以及网页 DOM / JavaScript 集成逻辑可能包含错误、遗漏或安全问题。维护者不保证项目的安全性、正确性、稳定性、可用性或适用于任何特定用途。

使用、登录、修改或分发本项目所产生的风险由使用者自行承担。

## License

项目代码使用 MIT License。

第三方库、图标、商标及其他第三方资源遵循其各自的许可证和权利声明。
