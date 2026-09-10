{
  pkgs,
  version ? "0.1.0",
  x86_64Package,
  aarch64Package,
}: let
  pname = "netease-music-webplayer";

  mkPackage = {
    package,
    arch,
    format,
  }:
    pkgs.runCommand "${pname}-${version}-${arch}-${format}" {
      nativeBuildInputs = [
        pkgs.nfpm
      ];
    } ''
      mkdir -p stage

      # Dereference Nix store symlinks so the generated distro package
      # does not contain references into /nix/store.
      cp -aL ${package}/. stage/

      chmod -R u+w stage

      cat > nfpm.yaml <<EOF
      name: ${pname}
      arch: ${arch}
      platform: linux
      version: ${version}

      maintainer: HumXC
      description: Netease Cloud Music Web Player
      homepage: https://github.com/HumXC/netease-music-webplayer
      license: MIT

      contents:
        - src: ./stage/
          dst: /
          type: tree
      EOF

      mkdir -p "$out"

      nfpm package \
        --config nfpm.yaml \
        --packager ${format} \
        --target "$out/"
    '';
in {
  deb-x86_64 = mkPackage {
    package = x86_64Package;
    arch = "amd64";
    format = "deb";
  };

  deb-aarch64 = mkPackage {
    package = aarch64Package;
    arch = "arm64";
    format = "deb";
  };

  rpm-x86_64 = mkPackage {
    package = x86_64Package;
    arch = "amd64";
    format = "rpm";
  };

  rpm-aarch64 = mkPackage {
    package = aarch64Package;
    arch = "arm64";
    format = "rpm";
  };

  arch-x86_64 = mkPackage {
    package = x86_64Package;
    arch = "amd64";
    format = "archlinux";
  };

  arch-aarch64 = mkPackage {
    package = aarch64Package;
    arch = "arm64";
    format = "archlinux";
  };
}
