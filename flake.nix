{
  description = "Netease Cloud Music WebKitGTK wrapper";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          gstPlugins = with pkgs.gst_all_1; [
            gstreamer
            gst-plugins-base
            gst-plugins-good
            gst-plugins-ugly
            gst-libav
          ];
          zigDeps = pkgs.linkFarm "netease-music-webplayer-zig-pkg" [
            {
              name = "gobject-0.3.1-Skun7JC5fAFWOaM_zWo3XZAw7wPa6GYKK6U76Yy_Jkvt";
              path = pkgs.runCommand "zig-gobject-bindings-gnome49" {
                nativeBuildInputs = [ pkgs.gnutar pkgs.zstd ];
                src = pkgs.fetchurl {
                  url = "https://github.com/ianprime0509/zig-gobject/releases/download/v0.3.1/bindings-gnome49.tar.zst";
                  hash = "sha256-xrAF938IIVovlj7yjZ+3Uz5CbuTmw6Rmgm5ctzEDsGY=";
                };
              } ''
                mkdir -p "$out"
                tar --zstd -xf "$src" -C "$out" --strip-components=1
              '';
            }
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
        in {
          default = pkgs.stdenv.mkDerivation {
            pname = "netease-music-webplayer";
            version = "0.1.0";
            src = builtins.path {
              path = ./.;
              name = "netease-music-webplayer-source";
            };

            nativeBuildInputs = with pkgs; [
              zig_0_16
              pkg-config
              python3
              wrapGAppsHook4
            ];

            buildInputs = with pkgs; [
              gtk4
              webkitgtk_6_0
              glib-networking
            ] ++ gstPlugins;

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

            preFixup = ''
              gappsWrapperArgs+=(
                --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : ${pkgs.lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" gstPlugins}
              )
            '';

            meta = with pkgs.lib; {
              description = "Netease Cloud Music WebKitGTK wrapper with tray controls";
              homepage = "https://music.163.com/st/webplayer";
              license = licenses.mit;
              platforms = platforms.linux;
              mainProgram = "netease-music-webplayer";
            };
          };
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/netease-music-webplayer";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          gstPlugins = with pkgs.gst_all_1; [
            gstreamer
            gst-plugins-base
            gst-plugins-good
            gst-plugins-ugly
            gst-libav
          ];
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              zig_0_16
              zls
              pkg-config
              gcc
              python3
              gtk4
              webkitgtk_6_0
              glib-networking
            ] ++ gstPlugins;

            GIO_EXTRA_MODULES = "${pkgs.glib-networking}/lib/gio/modules";
            GST_PLUGIN_SYSTEM_PATH_1_0 = pkgs.lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" gstPlugins;
          };
        });
    };
}
