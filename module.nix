self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude-desktop;
in
{
  options.programs.claude-desktop = {
    enable = lib.mkEnableOption "Claude Desktop";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop;
      defaultText = lib.literalExpression "claude-desktop.packages.\${system}.claude-desktop";
      description = "Claude Desktop package to install.";
    };

    code.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable nix-ld for the Claude Code binary downloaded by Claude Desktop.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [ cfg.package ];
        xdg.portal.enable = lib.mkDefault true;
        xdg.portal.extraPortals = lib.mkDefault [ pkgs.xdg-desktop-portal-gtk ];
      }

      (lib.mkIf cfg.code.enable {
        programs.nix-ld.enable = lib.mkDefault true;
      })
    ]
  );
}
