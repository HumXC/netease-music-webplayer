{
  linkFarm,
  applyPatches,
  fetchgit,
}:
linkFarm "zig-packages" [
  {
    name = "goose-2.0.0-e9MzMMUaAwDs4vGzB15VSOtkL_7tmfcfN8GoEiVbUbVZ";
    path = applyPatches {
      name = "goose-patched";

      src = fetchgit {
        url = "https://github.com/luxluth/goose";
        rev = "6e91762f8f0244295eff62071e37b7460bfc41ae";
        hash = "sha256-uEBm+jx5FVZ1vfrDr6HP3ik/9U/uabxUEznp+cpx+Tw=";
      };

      patches = [
        ./patches/goose-zig016.patch
      ];
    };
  }
  {
    name = "websocket-0.1.0-ZPISdWoTBQA8iviFsepUZiKrmT-oEyc-BwfbVzYwu7LO";
    path = fetchgit {
      url = "https://github.com/karlseguin/websocket.zig";
      rev = "efa879736bd438bea8b86a91f220ba408de57273";
      hash = "sha256-iwdF/j0ApqA4tVhOfnxVAlVhfsPcJGM4jdt6AOHHNjo=";
    };
  }
]
