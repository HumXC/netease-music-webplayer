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
      zigDeps = pkgs.linkFarm "netease-music-webplayer-zig-pkg" [
        {
          name = "goose-1.0.0-e9MzMGKcAgD7vlp_acJYt6g430wQcrAxUKWHEEF0_Hcc";
          path = pkgs.fetchFromGitHub {
            owner = "luxluth";
            repo = "goose";
            rev = "387de965800bf0f6116d51f45a9412cba0801975";
            hash = "sha256-SWx6eoQ47DcIdQEdTaKb7b2Rn/6qB+XhCYTBMtMrGGw=";
          };
        }
      ];
    in
      pkgs.stdenv.mkDerivation {
        pname = "netease-music-webplayer";
        version = "0.1.0";
        src = builtins.path {
          path = ./.;
          name = "netease-music-webplayer-source";
        };

        nativeBuildInputs = with pkgs; [
          zig_0_16
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

        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          runHook preInstall

          rm -rf zig-pkg
          cp -R --dereference ${zigDeps} zig-pkg
          chmod -R u+w zig-pkg

          export ZIG_GLOBAL_CACHE_DIR="$PWD/zig-pkg"
          export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache"
          zig build \
            -Doptimize=ReleaseSafe \
            --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" \
            --cache-dir "$ZIG_LOCAL_CACHE_DIR" \
            --prefix "$out" \
            install

          runHook postInstall
        '';

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
