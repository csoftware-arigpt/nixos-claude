{
  description = "Official Claude Desktop application packaged for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = package: nixpkgs.lib.getName package == "claude-desktop";
      };
      claude-desktop = pkgs.callPackage ./package.nix { };
      claudeApp = {
        type = "app";
        program = "${claude-desktop}/bin/claude-desktop";
        meta.description = claude-desktop.meta.description;
      };
    in
    {
      packages.${system} = {
        default = claude-desktop;
        inherit claude-desktop;
      };

      apps.${system} = {
        default = claudeApp;
        claude-desktop = claudeApp;
      };

      checks.${system}.package-smoke =
        pkgs.runCommand "claude-desktop-package-smoke"
          {
            nativeBuildInputs = [
              pkgs.desktop-file-utils
              pkgs.patchelf
            ];
          }
          ''
            bash ${./tests/package-smoke.sh} \
              ${claude-desktop} \
              ${claude-desktop.version}
            touch "$out"
          '';

      overlays.default = final: _previous: {
        claude-desktop = final.callPackage ./package.nix { };
      };

      nixosModules.default = import ./module.nix self;
      nixosModules.claude-desktop = self.nixosModules.default;

      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = [
          pkgs.actionlint
          pkgs.curl
          pkgs.dpkg
          pkgs.nixfmt
          pkgs.shellcheck
        ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
