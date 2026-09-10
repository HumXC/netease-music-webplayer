{
  description = "Netease Cloud Music WebKitGTK wrapper";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  nixConfig = {
    extra-substituters = [
      "https://netease-music-webplayer.cachix.org"
    ];
    extra-trusted-public-keys = [
      "netease-music-webplayer.cachix.org-1:PKEilRsFVSr1IXF0oFIoGTbJ3Lih7PYH5RII7w0ntzo="
    ];
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    mkPackage = pkgs: let
      lib = pkgs.lib;
      stdenv = pkgs.stdenv;
      deps = pkgs.callPackage ./deps.nix {};
      glibcVersion =
        lib.versions.majorMinor stdenv.cc.libc.version;

      target =
        if stdenv.hostPlatform.isx86_64
        then "x86_64-linux-gnu.${glibcVersion}"
        else if stdenv.hostPlatform.isAarch64
        then "aarch64-linux-gnu.${glibcVersion}"
        else throw "Unsupported system: ${stdenv.hostPlatform.system}";
    in
      stdenv.mkDerivation {
        pname = "netease-music-webplayer";
        version = "0.1.0";
        src = builtins.path {
          path = ./.;
          name = "netease-music-webplayer-source";
        };

        nativeBuildInputs = with pkgs; [
          zig
          sedutil
          pkg-config
          curlFull.dev
        ];

        desktopItems = [
          (pkgs.makeDesktopItem {
            name = "netease-music-webplayer";
            desktopName = "Netease Cloud Music";
            comment = "Netease Cloud Music Web Player";
            exec = "netease-music-webplayer";
            icon = "netease-cloud-music";
            terminal = false;
            categories = [
              "AudioVideo"
              "Audio"
              "Music"
              "Player"
            ];
            startupWMClass = "netease-music-webplayer";
          })
        ];

        buildInputs = with pkgs; [
          curlFull
        ];
        hardeningDisable = [
          "fortify"
        ];
        dontUseZigCheck = true;

        zigBuildFlags = [
          "--system"
          "${deps}"

          "-Doptimize=ReleaseFast"

          "-Dtarget=${target}"
        ];

        meta = with pkgs.lib; {
          description = "Netease Cloud Music WebKitGTK wrapper with tray controls";
          homepage = "https://music.163.com/st/webplayer";
          license = licenses.mit;
          platforms = platforms.linux;
          mainProgram = "netease-music-webplayer";
        };
      };
  in {
    overlays.default = final: prev: {
      netease-music-webplayer = mkPackage final;
    };

    packages = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = mkPackage pkgs;
      netease-music-webplayer = mkPackage pkgs;
    });

    apps = forAllSystems (system: {
      default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/netease-music-webplayer";
      };
    });

    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
          zig_0_16
          zls
          pkg-config
          curlFull.dev
        ];
      };
    });
  };
}
