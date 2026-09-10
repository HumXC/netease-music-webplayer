{
  description = "Netease Cloud Music Web Player";

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
    pname = "netease-music-webplayer";
    version = "0.1.0";

    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    forAllSystems = nixpkgs.lib.genAttrs systems;

    mkPackage = pkgs: target: let
      deps = pkgs.callPackage ./deps.nix {};
    in
      pkgs.stdenv.mkDerivation {
        inherit pname version;

        src = builtins.path {
          path = ./.;
          name = "${pname}-source";
        };

        nativeBuildInputs = with pkgs; [
          zig
          copyDesktopItems
        ];

        desktopItems = [
          (pkgs.makeDesktopItem {
            name = pname;
            desktopName = "Netease Cloud Music";
            comment = "Netease Cloud Music Web Player";
            exec = pname;
            icon = "netease-cloud-music";
            terminal = false;

            categories = [
              "AudioVideo"
              "Audio"
              "Music"
              "Player"
            ];

            startupWMClass = pname;
          })
        ];

        hardeningDisable = [
          "fortify"
        ];

        dontUseZigCheck = true;

        zigBuildFlags = [
          "--system"
          "${deps}"

          "-Doptimize=ReleaseSmall"
          "-Dtarget=${target}"
        ];

        postInstall = ''
          install -Dm644 \
            assets/netease-cloud-music.svg \
            $out/share/icons/hicolor/scalable/apps/netease-cloud-music.svg
        '';
        meta = with pkgs.lib; {
          description = "Netease Cloud Music Web Player";
          homepage = "https://music.163.com/st/webplayer";
          license = licenses.mit;
          platforms = platforms.linux;
          mainProgram = pname;
        };
      };
  in {
    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };

        nativeTarget =
          if pkgs.stdenv.hostPlatform.isx86_64
          then "x86_64-linux-musl"
          else if pkgs.stdenv.hostPlatform.isAarch64
          then "aarch64-linux-musl"
          else throw "Unsupported system: ${system}";

        nativePackage =
          mkPackage pkgs nativeTarget;

        x86_64Package =
          mkPackage pkgs "x86_64-linux-musl";

        aarch64Package =
          mkPackage pkgs "aarch64-linux-musl";

        distPackages = import ./packaging.nix {
          inherit
            pkgs
            version
            x86_64Package
            aarch64Package
            ;
        };
      in
        {
          default = nativePackage;

          netease-music-webplayer =
            nativePackage;

          x86_64-linux =
            x86_64Package;

          aarch64-linux =
            aarch64Package;
        }
        // distPackages
    );

    apps = forAllSystems (
      system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/${pname}";
        };
      }
    );

    devShells = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        default = pkgs.mkShell {
          packages = with pkgs; [
            zig_0_16
            zls
          ];
        };
      }
    );
  };
}
