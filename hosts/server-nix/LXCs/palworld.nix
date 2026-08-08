{ config, self, ... }:
{
  imports = [
    ./base
    "${self}/modules/software/services/palworld.nix"
  ];

  my.secrets.palworld_env.enable = true;

  services.palworld = {
    enable = true;
    autoStart = true;
    environmentFile = config.sops.secrets.palworld_env.path;

    serverName = "THE DOJO";
    serverDescription = "hehehe fnuny pokemon :)";
    maxPlayers = 16;

    rcon = {
      enable = true;
      openFirewall = false;
    };

    # TEMPORARY: easy mode for a corpse run (high-level pals camping a death drop).
    # Delete this whole extraSettings block and redeploy to go back to normal.
    extraSettings = {
      # Don't lose anything if the retrieval attempt goes badly.
      DeathPenalty = "None";
      bCanPickupOtherGuildDeathPenaltyDrop = "True";
      # Keep the existing bag on the ground instead of despawning after 1h.
      DropItemAliveMaxHours = "24.000000";
      DropItemMaxNum = "5000";

      # Hit like a truck, take almost nothing.
      PlayerDamageRateAttack = "5.000000";
      PlayerDamageRateDefense = "0.100000";
      PalDamageRateAttack = "5.000000";
      PalDamageRateDefense = "0.100000";

      # No starving/gassing out mid-run, and heal back fast.
      PlayerAutoHPRegeneRate = "5.000000";
      PlayerAutoHpRegeneRateInSleep = "5.000000";
      PlayerStomachDecreaceRate = "0.100000";
      PlayerStaminaDecreaceRate = "0.100000";
      PalAutoHPRegeneRate = "5.000000";
      PalAutoHpRegeneRateInSleep = "5.000000";
      PalStomachDecreaceRate = "0.100000";
      PalStaminaDecreaceRate = "0.100000";

      # Thin out the camping party and stop raids from piling on.
      PalSpawnNumRate = "0.100000";
      bEnableInvaderEnemy = "False";
    };
  };

  networking.hostName = "palworld-nix";
}
